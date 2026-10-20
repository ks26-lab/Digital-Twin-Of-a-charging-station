function comp_results = compare_allocation_strategies(user_vehicles, user_station, cfg)
% COMPARE_ALLOCATION_STRATEGIES Rigorous non-destructive head-to-head comparison
% of station-level power allocation strategies using identical initial conditions.
%
% Compares:
%   1. Strategy A: Equal Allocation (Equal distribution with headroom reallocation)
%   2. Strategy B: Energy-Aware Proportional Allocation
%   3. Strategy C: Predictive Completion-Time Optimization (Min-Max Makespan)
%
% Under:
%   - Identical initial vehicle states (Capacity, SOC, SOH, Temp, Resistance)
%   - Identical station power budget (P_station)
%   - Individual charger continuous limits (4.5 kW, 85 A, 58 V)
%   - Physical Li-ion battery and BMS thermal & stress dynamics
%
% Usage:
%   comp_results = compare_allocation_strategies(); % Uses default fleet
%   comp_results = compare_allocation_strategies(vehicles, station_cfg, cfg);

if nargin < 3 || isempty(cfg)
    cfg = station_config();
end

if nargin < 1 || isempty(user_vehicles)
    user_vehicles = cfg.default_user_vehicles;
end

if nargin < 2 || isempty(user_station)
    user_station.grid_power_limit = cfg.station.grid_power_limit;
    user_station.num_vehicles = min(4, length(user_vehicles));
    user_station.bms_strategy = 'adaptive';
    user_station.dt = 1.0;
end

P_limit = user_station.grid_power_limit;
N_veh   = user_station.num_vehicles;

fprintf('\n=================================================================\n');
fprintf('  MULTI-STRATEGY POWER ALLOCATION COMPARISON AUDIT\n');
fprintf('=================================================================\n');
fprintf('  Station Power Limit : %.1f kW\n', P_limit);
fprintf('  Number of Vehicles  : %d Active Chargers\n', N_veh);
fprintf('  BMS Strategy        : %s C-rate control\n', upper(user_station.bms_strategy));
fprintf('-----------------------------------------------------------------\n');

strategies = {'equal', 'energy_aware', 'predictive_opt'};
strategy_names = {'Strategy A (Equal)', 'Strategy B (Energy-Aware)', 'Strategy C (Predictive Min-Max)'};

comp_results.strategies = strategies;
comp_results.strategy_names = strategy_names;
comp_results.runs = repmat(struct(), 3, 1);

for s = 1:3
    strat = strategies{s};
    strat_name = strategy_names{s};
    
    % Initialize identical fleet for this strategy run
    sim_cfg = cfg;
    sim_cfg.station.grid_power_limit = P_limit;
    sim_cfg.station.strategy = strat;
    
    sim_vehs = [];
    chargers = repmat(struct(), N_veh, 1);
    connectors = repmat(struct(), N_veh, 1);
    
    for i = 1:N_veh
        v_in = user_vehicles(i);
        v = vehicle_manager.create_vehicle(v_in, sim_cfg);
        v.state = "CHARGING";
        v.assigned_bay = i;
        sim_vehs = [sim_vehs, v];
        
        chargers(i).id = i;
        chargers(i).bay_id = i;
        chargers(i).status = "CHARGING";
        chargers(i).I_out = 0.0;
        chargers(i).V_out = 0.0;
        chargers(i).P_out_kW = 0.0;
        chargers(i).P_grid_kW = 0.0;
        chargers(i).energy_delivered_kWh = 0.0;
        chargers(i).fault_active = false;
        chargers(i).fault_msg = "Normal";
        
        connectors(i) = connector_manager.init_connector(i, i);
        connectors(i).state = "LOCKED";
        connectors(i).electrical_connected = true;
    end
    
    % 1. Evaluate Initial Dynamic Allocation & Completion-Time Predictions
    [alloc_kW, T_pred_sec, diag] = station_power_allocator.allocate_power(...
        sim_vehs, chargers, connectors, strat, sim_cfg);
    
    % 2. Run Accelerated Closed-Loop Discrete Simulation until all active reach target
    dt_step = 2.0; % Accelerated 2s step for rapid analytical resolution
    sim_t = 0.0;
    max_sim_t = 7200.0; % 2 hours cap
    
    peak_T_arr = [sim_vehs.battery.Temperature];
    peak_BSI_arr = zeros(N_veh, 1);
    completion_times = inf(N_veh, 1);
    
    pred_model = predictive_analytics.get_model();
    
    while sim_t < max_sim_t
        % Check if all enabled vehicles have reached target SOC
        all_done = true;
        for i = 1:N_veh
            if sim_vehs(i).is_enabled && sim_vehs(i).battery.SOC < sim_vehs(i).battery.target_SOC
                all_done = false;
                break;
            end
        end
        if all_done; break; end
        
        % Dynamic Station Power Allocation at each step
        [cur_alloc_kW, ~, ~] = station_power_allocator.allocate_power(...
            sim_vehs, chargers, connectors, strat, sim_cfg);
        
        for i = 1:N_veh
            veh = sim_vehs(i);
            if ~veh.is_enabled || veh.battery.SOC >= veh.battery.target_SOC
                if isinf(completion_times(i)) && veh.battery.SOC >= veh.battery.target_SOC
                    completion_times(i) = sim_t;
                end
                chargers(i).I_out = 0.0;
                chargers(i).P_out_kW = 0.0;
                continue;
            end
            
            % OCV Lookup
            OCV = interp1(sim_cfg.battery.SOC_table, sim_cfg.battery.OCV_table, veh.battery.SOC, 'pchip');
            
            % Proactive predictive advisory
            [~, ~, C_max_advice, ~] = predictive_analytics.forecast(pred_model, veh.battery, 100, sim_cfg);
            veh.battery.C_max_advice = C_max_advice;
            
            % BMS controller
            [bms_cmd, bsi_data, ~] = bms_controller(...
                veh.battery, OCV, veh.prev_I_cmd, dt_step, user_station.bms_strategy, veh.battery.target_SOC, sim_cfg);
            
            % Charger output
            [chargers(i), I_deliv, P_deliv_kW, ~] = charger_model(...
                chargers(i), bms_cmd.I_cmd, veh.battery.Voltage, true, cur_alloc_kW(i), dt_step, sim_cfg);
            
            % Battery update
            [veh.battery, ~] = battery_model(veh.battery, I_deliv, dt_step, sim_cfg);
            
            veh.prev_I_cmd = I_deliv;
            veh.I_cmd = bms_cmd.I_cmd;
            veh.BSI = bsi_data.BSI;
            veh.P_alloc_kW = cur_alloc_kW(i);
            veh.P_delivered_kW = P_deliv_kW;
            
            peak_T_arr(i) = max(peak_T_arr(i), veh.battery.Temperature);
            peak_BSI_arr(i) = max(peak_BSI_arr(i), veh.BSI);
            
            if veh.battery.SOC >= veh.battery.target_SOC && isinf(completion_times(i))
                completion_times(i) = sim_t + dt_step;
            end
            
            sim_vehs(i) = veh;
        end
        
        sim_t = sim_t + dt_step;
    end
    
    % Record metrics
    comp_results.runs(s).strategy = strat;
    comp_results.runs(s).name = strat_name;
    comp_results.runs(s).initial_alloc_kW = alloc_kW;
    comp_results.runs(s).initial_pred_time_min = T_pred_sec / 60.0;
    comp_results.runs(s).initial_pred_makespan_min = diag.makespan_sec / 60.0;
    comp_results.runs(s).actual_sim_time_sec = sim_t;
    comp_results.runs(s).actual_makespan_min = max(completion_times) / 60.0;
    comp_results.runs(s).vehicle_completion_min = completion_times / 60.0;
    comp_results.runs(s).total_energy_kWh = sum([chargers.energy_delivered_kWh]);
    comp_results.runs(s).peak_temperatures = peak_T_arr;
    comp_results.runs(s).peak_BSI = peak_BSI_arr;
    
    fprintf('\n--- %s ---\n', strat_name);
    for i = 1:N_veh
        fprintf('  Veh #%d (%s, %d Ah): Init Alloc = %.2f kW | Fin Time = %.1f min | Peak T = %.1f °C | Peak BSI = %.1f\n', ...
            sim_vehs(i).id, sim_vehs(i).type_name, round(sim_vehs(i).battery.Q_nom), ...
            alloc_kW(i), completion_times(i)/60.0, peak_T_arr(i), peak_BSI_arr(i));
    end
    fprintf('  Actual Station Makespan (T_finish) : %.1f min\n', max(completion_times)/60.0);
    fprintf('  Total Energy Delivered             : %.3f kWh\n', comp_results.runs(s).total_energy_kWh);
end

% Summary & Optimization Gain
makespan_equal = comp_results.runs(1).actual_makespan_min;
makespan_energy = comp_results.runs(2).actual_makespan_min;
makespan_pred = comp_results.runs(3).actual_makespan_min;

reduction_vs_equal = 0.0;
if makespan_equal > 0
    reduction_vs_equal = ((makespan_equal - makespan_pred) / makespan_equal) * 100.0;
end

comp_results.reduction_pct_vs_equal = reduction_vs_equal;

fprintf('\n=================================================================\n');
fprintf('  SUMMARY COMPARISON TABLE\n');
fprintf('=================================================================\n');
fprintf('  Strategy               | Makespan (min) | Energy (kWh) | Time Savings vs Equal\n');
fprintf('  ---------------------------------------------------------------\n');
fprintf('  A: Equal Share         |    %6.1f min  |   %6.2f kWh  |   Baseline (0.0%%)\n', makespan_equal, comp_results.runs(1).total_energy_kWh);
fprintf('  B: Energy-Aware        |    %6.1f min  |   %6.2f kWh  |   %+.1f%%\n', makespan_energy, comp_results.runs(2).total_energy_kWh, ((makespan_equal - makespan_energy)/makespan_equal)*100);
fprintf('  C: Predictive Min-Max  |    %6.1f min  |   %6.2f kWh  |   %+.1f%% (Best)\n', makespan_pred, comp_results.runs(3).total_energy_kWh, reduction_vs_equal);
fprintf('=================================================================\n\n');

end
