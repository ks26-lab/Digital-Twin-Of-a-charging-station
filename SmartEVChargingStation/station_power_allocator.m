classdef station_power_allocator
    % STATION_POWER_ALLOCATOR Central station grid controller that optimizes
    % dynamic power distribution across multiple concurrently charging EVs.
    %
    % Implements 3 distinct station-level allocation algorithms:
    %   1. Strategy A: Equal Allocation (with iterative headroom redistribution)
    %   2. Strategy B: Energy-Aware Proportional Allocation
    %   3. Strategy C: Predictive Completion-Time Optimization (Min-Max Makespan)
    %
    % Primary Optimization Objective:
    %   minimize T_finish = max(T_1, T_2, ..., T_N)
    %   subject to:
    %     0 <= P_i <= P_max_safe,i
    %     sum(P_i) <= P_station
    
    methods (Static)
        function [alloc_kW, T_pred_sec, diag] = allocate_power(vehicles, chargers, connectors, strategy, cfg)
            num_chargers = cfg.charger.num_chargers;
            alloc_kW     = zeros(num_chargers, 1);
            T_pred_sec   = zeros(num_chargers, 1);
            P_grid_limit = cfg.station.grid_power_limit; % Total station budget [kW]
            
            % 1. Identify Eligible Connected Vehicles
            eligible_chargers = [];
            eligible_v_indices = [];
            E_rem_arr         = [];
            P_max_arr         = [];
            
            for c = 1:num_chargers
                bay_id = chargers(c).bay_id;
                v_idx  = find([vehicles.assigned_bay] == bay_id, 1);
                
                if ~isempty(v_idx)
                    veh = vehicles(v_idx);
                    is_locked = connectors(c).electrical_connected;
                    
                    % Check user vehicle enable/disable flag
                    is_veh_enabled = true;
                    if isfield(veh, 'is_enabled')
                        is_veh_enabled = veh.is_enabled;
                    elseif isfield(veh.battery, 'is_enabled')
                        is_veh_enabled = veh.battery.is_enabled;
                    end
                    
                    % Eligibility criteria: locked connector, enabled, charging state, SOC < target, no critical fault
                    is_eligible = is_locked && is_veh_enabled && ...
                                  (strcmpi(veh.state, "CHARGING") || strcmpi(veh.state, "CONNECTED")) && ...
                                  (veh.battery.SOC < veh.battery.target_SOC) && ...
                                  (~veh.battery.is_overtemp) && ...
                                  (~veh.battery.is_overvoltage) && ...
                                  (veh.BSI < cfg.bsi.trip_threshold) && ...
                                  (~chargers(c).fault_active);
                              
                    if is_eligible
                        eligible_chargers  = [eligible_chargers; c];
                        eligible_v_indices = [eligible_v_indices; v_idx];
                        
                        % Calculate remaining energy and maximum safe power
                        [~, E_rem, P_max_safe] = charging_time_predictor.predict_completion_time(...
                            veh.battery, cfg.charger.P_max, veh.battery.target_SOC, cfg);
                        
                        E_rem_arr = [E_rem_arr; max(E_rem, 0.01)];
                        P_max_arr = [P_max_arr; P_max_safe];
                    end
                end
            end
            
            N_elig = length(eligible_chargers);
            if N_elig == 0
                % No active vehicles requiring charge
                diag.strategy = strategy;
                diag.total_allocated_kW = 0.0;
                diag.unallocated_kW = P_grid_limit;
                diag.makespan_sec = 0.0;
                diag.eligible_count = 0;
                return;
            end
            
            % 2. Execute Selected Power Allocation Strategy
            switch lower(strategy)
                case 'equal'
                    % --- STRATEGY A: EQUAL SHARING WITH HEADROOM REALLOCATION ---
                    P_alloc_elig = station_power_allocator.solve_equal_allocation(...
                        P_grid_limit, P_max_arr);
                    
                case 'energy_aware'
                    % --- STRATEGY B: REMAINING ENERGY-PROPORTIONAL ALLOCATION ---
                    P_alloc_elig = station_power_allocator.solve_energy_aware_allocation(...
                        P_grid_limit, E_rem_arr, P_max_arr);
                    
                case 'predictive_opt'
                    % --- STRATEGY C: PREDICTIVE COMPLETION-TIME OPTIMIZATION ---
                    P_alloc_elig = station_power_allocator.solve_minmax_completion_time(...
                        vehicles(eligible_v_indices), P_grid_limit, E_rem_arr, P_max_arr, cfg);
                    
                otherwise
                    % Default fallback to predictive optimization
                    P_alloc_elig = station_power_allocator.solve_minmax_completion_time(...
                        vehicles(eligible_v_indices), P_grid_limit, E_rem_arr, P_max_arr, cfg);
            end
            
            % 3. Map Allocations to Charger Hardware Channels & Predict Completion Times
            for i = 1:N_elig
                c_idx = eligible_chargers(i);
                v_idx = eligible_v_indices(i);
                alloc_kW(c_idx) = P_alloc_elig(i);
                
                % Compute non-linear predicted time to target SOC
                T_pred_sec(c_idx) = charging_time_predictor.predict_completion_time(...
                    vehicles(v_idx).battery, P_alloc_elig(i), vehicles(v_idx).battery.target_SOC, cfg);
            end
            
            % 4. Diagnostics & Station Level Metrics
            diag.strategy = strategy;
            diag.eligible_count = N_elig;
            diag.total_allocated_kW = sum(alloc_kW);
            diag.unallocated_kW = max(0.0, P_grid_limit - diag.total_allocated_kW);
            diag.makespan_sec = max(T_pred_sec(eligible_chargers));
            diag.average_completion_sec = mean(T_pred_sec(eligible_chargers));
            diag.eligible_chargers = eligible_chargers;
            diag.E_rem_arr = E_rem_arr;
            diag.P_max_arr = P_max_arr;
        end
        
        function P_alloc = solve_equal_allocation(P_total, P_max_arr)
            % Distributes available power equally, iteratively redistributing headroom
            N = length(P_max_arr);
            P_alloc = zeros(N, 1);
            unconstrained = true(N, 1);
            P_remaining = P_total;
            
            for iter = 1:N
                if ~any(unconstrained) || P_remaining <= 1e-4; break; end
                
                P_share = P_remaining / sum(unconstrained);
                newly_constrained = false;
                
                for i = 1:N
                    if unconstrained(i)
                        if P_share >= P_max_arr(i)
                            P_alloc(i) = P_max_arr(i);
                            P_remaining = P_remaining - P_max_arr(i);
                            unconstrained(i) = false;
                            newly_constrained = true;
                        end
                    end
                end
                
                if ~newly_constrained
                    % All remaining unconstrained vehicles receive equal share
                    P_alloc(unconstrained) = P_share;
                    P_remaining = 0;
                    break;
                end
            end
        end
        
        function P_alloc = solve_energy_aware_allocation(P_total, E_rem_arr, P_max_arr)
            % Allocates power proportionally to remaining energy E_rem
            N = length(E_rem_arr);
            P_alloc = zeros(N, 1);
            unconstrained = true(N, 1);
            P_remaining = P_total;
            
            for iter = 1:N
                if ~any(unconstrained) || P_remaining <= 1e-4; break; end
                
                E_sub_total = sum(E_rem_arr(unconstrained));
                if E_sub_total <= 0
                    P_alloc(unconstrained) = P_remaining / sum(unconstrained);
                    break;
                end
                
                newly_constrained = false;
                for i = 1:N
                    if unconstrained(i)
                        P_desired = P_remaining * (E_rem_arr(i) / E_sub_total);
                        if P_desired >= P_max_arr(i)
                            P_alloc(i) = P_max_arr(i);
                            P_remaining = P_remaining - P_max_arr(i);
                            unconstrained(i) = false;
                            newly_constrained = true;
                        end
                    end
                end
                
                if ~newly_constrained
                    % Proportional assignment for unconstrained
                    for i = 1:N
                        if unconstrained(i)
                            P_alloc(i) = P_remaining * (E_rem_arr(i) / E_sub_total);
                        end
                    end
                    break;
                end
            end
            P_alloc = min(P_alloc, P_max_arr);
        end
        
        function P_alloc = solve_minmax_completion_time(eligible_vehicles, P_total, E_rem_arr, P_max_arr, cfg)
            % Solves min { max_i T_i(P_i) } s.t. sum(P_i) <= P_total, 0 <= P_i <= P_max,i
            %
            % Mathematical Formulation:
            % The bottleneck completion time is minimized when all completion times are equalized:
            % T_1(P_1) = T_2(P_2) = ... = T_N(P_N) = T*
            % We search for the optimal target makespan T* via bisection root-finding on:
            % sum( P_req,i(T*) ) = P_total
            
            N = length(eligible_vehicles);
            P_alloc = zeros(N, 1);
            
            % If total max capability is less than station budget, give everyone max
            if sum(P_max_arr) <= P_total
                P_alloc = P_max_arr;
                return;
            end
            
            % Bisection bounds for target completion time T* [seconds]
            % Lower bound: shortest possible time if entire station power went to least energy car
            T_low  = max(min(E_rem_arr) / (P_total / 3600), 10.0);
            % Upper bound: time if everyone charged at 0.2 kW trickle
            T_high = max(E_rem_arr) / (0.2 / 3600);
            
            T_star = T_high;
            for iter = 1:25
                T_mid = (T_low + T_high) / 2.0;
                
                % Calculate power required by each vehicle to finish at T_mid
                P_req_sum = 0.0;
                for i = 1:N
                    veh = eligible_vehicles(i);
                    P_req = charging_time_predictor.calculate_power_for_target_time(...
                        veh.battery, T_mid, veh.battery.target_SOC, cfg);
                    P_req_sum = P_req_sum + min(P_req, P_max_arr(i));
                end
                
                if P_req_sum > P_total
                    % Demands too much power -> completion time must be longer
                    T_low = T_mid;
                else
                    % Power demand fits within budget -> can achieve shorter completion time
                    T_high = T_mid;
                    T_star = T_mid;
                end
            end
            
            % Compute candidate allocations at optimal T*
            for i = 1:N
                veh = eligible_vehicles(i);
                P_req = charging_time_predictor.calculate_power_for_target_time(...
                    veh.battery, T_star, veh.battery.target_SOC, cfg);
                P_alloc(i) = min(P_req, P_max_arr(i));
            end
            
            % Water-fill any remaining slack power to vehicles not at P_max
            P_slack = max(0.0, P_total - sum(P_alloc));
            if P_slack > 0.05
                headroom = P_max_arr - P_alloc;
                can_take = headroom > 0.01;
                if any(can_take)
                    P_alloc(can_take) = P_alloc(can_take) + (P_slack / sum(can_take));
                    P_alloc = min(P_alloc, P_max_arr);
                end
            end
        end
    end
end
