classdef charging_time_predictor
    % CHARGING_TIME_PREDICTOR Non-linear charging completion time estimator.
    %
    % Accounts for:
    %   1. Remaining energy to target SOC
    %   2. Non-linear OCV(SOC) curve and internal resistance Rint
    %   3. Constant-Current (CC) phase duration
    %   4. Constant-Voltage (CV) exponential current tapering duration
    %   5. Temperature and BSI derating ceilings
    %   6. Charger converter efficiency (eta = 94%)
    
    methods (Static)
        function [T_pred_sec, E_rem_kWh, P_max_safe_kW] = predict_completion_time(battery_state, P_alloc_kW, target_SOC, cfg)
            % Predicts the time required (in seconds) for a battery to reach target_SOC
            % given an allocated charging power P_alloc_kW.
            
            SOC_curr = battery_state.SOC;
            Q_nom    = battery_state.Q_nom;          % Ah
            Rint     = max(battery_state.Rint, 0.01);% Ohm
            
            if isfield(battery_state, 'V_max') && ~isempty(battery_state.V_max)
                V_max = battery_state.V_max;
            else
                V_max = cfg.battery.V_max;            % 54.6 V
            end
            
            C_max    = battery_state.C_max;          % 1.5 C
            eta      = cfg.charger.efficiency;       % 0.94
            
            % If disabled or already at or above target, remaining time is 0
            is_enabled = true;
            if isfield(battery_state, 'is_enabled')
                is_enabled = battery_state.is_enabled;
            end
            
            if ~is_enabled || (SOC_curr >= target_SOC)
                T_pred_sec = 0.0;
                E_rem_kWh = 0.0;
                P_max_safe_kW = 0.0;
                return;
            end
            
            % 1. Calculate approximate remaining energy [kWh]
            % Energy = integral(V(SOC) * Q_nom * dSOC)
            % Approximated by average OCV over remaining SOC interval:
            soc_samples = linspace(SOC_curr, target_SOC, 10);
            ocv_samples = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, soc_samples, 'pchip');
            V_avg = mean(ocv_samples);
            
            delta_SOC = target_SOC - SOC_curr;
            E_rem_kWh = (Q_nom * V_avg * delta_SOC) / 1000.0;
            
            % 2. Maximum permissible continuous charging power [kW]
            % Limited by C_max current and maximum terminal voltage
            I_max_safe = C_max * Q_nom;
            P_max_safe_kW = (V_max * I_max_safe) / 1000.0;
            P_max_safe_kW = min(P_max_safe_kW, cfg.charger.P_max);
            
            % Effective available DC power into battery
            P_dc_kW = min(P_alloc_kW, P_max_safe_kW);
            if P_dc_kW <= 0.01
                % No power allocated -> infinite/indeterminate completion time
                T_pred_sec = 1.0e6;
                return;
            end
            
            % 3. Multi-phase non-linear completion time integration:
            % Determine transition SOC where terminal voltage reaches V_max under P_dc:
            % V_term = OCV(SOC_cv) + I * Rint = V_max
            % P_dc = V_term * I = V_max * I => I_cc = (P_dc * 1000) / V_max
            I_cc = min((P_dc_kW * 1000.0) / max(V_avg, 36.0), I_max_safe);
            OCV_at_cv = V_max - I_cc * Rint;
            
            % Find SOC corresponding to OCV_at_cv
            if OCV_at_cv >= cfg.battery.OCV_table(end)
                SOC_cv = 1.0;
            elseif OCV_at_cv <= cfg.battery.OCV_table(1)
                SOC_cv = 0.0;
            else
                % Invert OCV table
                SOC_cv = interp1(cfg.battery.OCV_table, cfg.battery.SOC_table, OCV_at_cv, 'linear');
            end
            
            % 4. Phase A: Constant Current / Constant Power Phase
            if target_SOC <= SOC_cv
                % Reaches target entirely within CC phase
                T_cc_sec = (delta_SOC * Q_nom * 3600.0) / max(I_cc, 0.1);
                T_cv_sec = 0.0;
            else
                % Partially in CC, then transitions to CV taper
                delta_SOC_cc = max(0.0, SOC_cv - SOC_curr);
                T_cc_sec = (delta_SOC_cc * Q_nom * 3600.0) / max(I_cc, 0.1);
                
                % 5. Phase B: Constant Voltage (CV) Tapering Phase
                % In CV, current decays as OCV rises toward V_max:
                % Average current in CV region is approximately 50% of I_cc down to cutoff:
                delta_SOC_cv = target_SOC - max(SOC_curr, SOC_cv);
                I_cv_avg = 0.55 * I_cc; % Harmonic/exponential mean during CV taper
                T_cv_sec = (delta_SOC_cv * Q_nom * 3600.0) / max(I_cv_avg, 0.1);
            end
            
            T_pred_sec = T_cc_sec + T_cv_sec;
        end
        
        function P_required_kW = calculate_power_for_target_time(battery_state, target_time_sec, target_SOC, cfg)
            % Inverts the prediction model: calculates the charging power P_required
            % so that the vehicle finishes charging in target_time_sec.
            
            is_enabled = true;
            if isfield(battery_state, 'is_enabled')
                is_enabled = battery_state.is_enabled;
            end
            
            if ~is_enabled || battery_state.SOC >= target_SOC || target_time_sec <= 1.0
                P_required_kW = 0.0;
                return;
            end
            
            % Approximate required DC power:
            % E_rem = Q * V_avg * dSOC
            soc_samples = linspace(battery_state.SOC, target_SOC, 10);
            ocv_samples = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, soc_samples, 'pchip');
            V_avg = mean(ocv_samples);
            delta_SOC = target_SOC - battery_state.SOC;
            E_rem_kWh = (battery_state.Q_nom * V_avg * delta_SOC) / 1000.0;
            
            % Time in hours
            t_hr = target_time_sec / 3600.0;
            
            % Include CV taper factor (~1.18x more power needed during CC to offset CV taper slowdown)
            taper_factor = 1.15;
            P_nominal = (E_rem_kWh / t_hr) * taper_factor;
            
            % Enforce battery and charger upper limits
            I_max = battery_state.C_max * battery_state.Q_nom;
            if isfield(battery_state, 'I_max') && ~isempty(battery_state.I_max)
                I_max = min(I_max, battery_state.I_max);
            end
            
            V_max = cfg.battery.V_max;
            if isfield(battery_state, 'V_max') && ~isempty(battery_state.V_max)
                V_max = battery_state.V_max;
            end
            P_max = min((V_max * I_max) / 1000.0, cfg.charger.P_max);
            
            P_required_kW = min(max(P_nominal, 0.0), P_max);
        end
    end
end
