function results = test_fixed_vs_adaptive()
% TEST_FIXED_VS_ADAPTIVE Controlled comparative experiment testing Fixed 1C
% vs Adaptive C-Rate charging under strictly identical initial conditions.
%
% Initial Conditions:
%   - Battery: 48V, 50Ah Li-ion pack
%   - Initial SOC: 20.0%
%   - Target SOC:  90.0%
%   - Initial Temp: 25.0 deg C
%   - Initial SOH: 95.0%

fprintf('=================================================================\n');
fprintf('  CONTROLLED EXPERIMENT: FIXED 1C VS ADAPTIVE C-RATE CHARGING\n');
fprintf('=================================================================\n\n');

cfg = station_config();
dt = 1.0; % 1 second resolution
t_max = 5400; % 90 minutes max

%% 1. Run Fixed 1C Charging Simulation
fprintf('Running Fixed 1C Charging baseline...\n');
fixed = run_single_charge_profile('fixed', cfg, dt, t_max);

%% 2. Run Stress-Aware Adaptive C-Rate Simulation
fprintf('Running Stress-Aware Adaptive C-Rate experiment...\n');
adaptive = run_single_charge_profile('adaptive', cfg, dt, t_max);

%% 3. Display Performance Comparison Table
speedup_pct = ((fixed.charge_time - adaptive.charge_time) / fixed.charge_time) * 100.0;
temp_reduction = fixed.max_temp - adaptive.max_temp;
bsi_reduction  = fixed.max_bsi  - adaptive.max_bsi;
soh_preserved  = (adaptive.final_soh - fixed.final_soh) * 100.0;

fprintf('\n=================================================================\n');
fprintf('  EXPERIMENTAL COMPARISON SUMMARY TABLE\n');
fprintf('=================================================================\n');
fprintf('  %-26s %-16s %-16s %-12s\n', 'Metric', 'Fixed 1C', 'Adaptive C-Rate', 'Advantage');
fprintf('  %s\n', repmat('-', 1, 72));
fprintf('  %-26s %-16.2f %-16.2f %+.2f min\n', 'Charge Time (min)', fixed.charge_time/60, adaptive.charge_time/60, (adaptive.charge_time - fixed.charge_time)/60);
fprintf('  %-26s %-16.2f %-16.2f %+.2f %%\n', 'Charging Speedup (%)', 0.0, speedup_pct, speedup_pct);
fprintf('  %-26s %-16.2f %-16.2f %.2f%%\n', 'Final SOC (%)', fixed.final_soc*100, adaptive.final_soc*100, 0.0);
fprintf('  %-26s %-16.2f %-16.2f -%.2f °C\n', 'Peak Temperature (°C)', fixed.max_temp, adaptive.max_temp, temp_reduction);
fprintf('  %-26s %-16.2f %-16.2f -%.2f / 100\n', 'Peak Battery Stress (BSI)', fixed.max_bsi, adaptive.max_bsi, bsi_reduction);
fprintf('  %-26s %-16.4f %-16.4f %+.4f %%\n', 'Final SOH (%)', fixed.final_soh*100, adaptive.final_soh*100, soh_preserved);
fprintf('  %-26s %-16.3f %-16.3f %+.3f kWh\n', 'Energy Delivered (kWh)', fixed.energy_delivered_kWh, adaptive.energy_delivered_kWh, adaptive.energy_delivered_kWh - fixed.energy_delivered_kWh);
fprintf('=================================================================\n\n');

results.fixed = fixed;
results.adaptive = adaptive;
results.speedup_pct = speedup_pct;
results.temp_reduction = temp_reduction;
results.bsi_reduction = bsi_reduction;

end

function res = run_single_charge_profile(strategy, cfg, dt, t_max)
    % Runs isolated single charging profile under identical parameters
    state.SOC = 0.20;
    state.SOH = 0.95;
    state.Temperature = 25.0;
    state.Q_nom = 50.0;
    state.R_initial = 0.050;
    state.C_max = 1.5;
    state.Rint = 0.050;
    state.Voltage = 42.8;
    state.Current = 0.0;
    state.Power = 0.0;
    state.energy_kWh = 0.0;
    state.is_overvoltage = false;
    state.is_overtemp = false;
    
    target_SOC = 0.90;
    prev_I = 0.0;
    
    N = floor(t_max / dt);
    time_arr = zeros(N, 1);
    soc_arr  = zeros(N, 1);
    temp_arr = zeros(N, 1);
    curr_arr = zeros(N, 1);
    volt_arr = zeros(N, 1);
    bsi_arr  = zeros(N, 1);
    crate_arr= zeros(N, 1);
    
    actual_steps = N;
    for k = 1:N
        t = (k - 1) * dt;
        time_arr(k) = t;
        
        OCV = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, state.SOC, 'pchip');
        [cmd, bsi_data, fault] = bms_controller(state, OCV, prev_I, dt, strategy, target_SOC, cfg);
        
        % Ideal charger delivering commanded current
        I_actual = cmd.I_cmd;
        [state, ~] = battery_model(state, I_actual, dt, cfg);
        prev_I = I_actual;
        
        soc_arr(k)   = state.SOC;
        temp_arr(k)  = state.Temperature;
        curr_arr(k)  = I_actual;
        volt_arr(k)  = state.Voltage;
        bsi_arr(k)   = bsi_data.BSI;
        crate_arr(k) = cmd.C_rate_cmd;
        
        if state.SOC >= target_SOC || fault.active
            actual_steps = k;
            break;
        end
    end
    
    res.time     = time_arr(1:actual_steps);
    res.SOC      = soc_arr(1:actual_steps);
    res.Temp     = temp_arr(1:actual_steps);
    res.Current  = curr_arr(1:actual_steps);
    res.Voltage  = volt_arr(1:actual_steps);
    res.BSI      = bsi_arr(1:actual_steps);
    res.C_rate   = crate_arr(1:actual_steps);
    
    res.charge_time = time_arr(actual_steps);
    res.final_soc   = state.SOC;
    res.final_soh   = state.SOH;
    res.max_temp    = max(temp_arr(1:actual_steps));
    res.max_bsi     = max(bsi_arr(1:actual_steps));
    res.energy_delivered_kWh = state.energy_kWh;
end
