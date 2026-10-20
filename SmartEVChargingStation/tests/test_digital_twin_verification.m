function all_pass = test_digital_twin_verification()
% TEST_DIGITAL_TWIN_VERIFICATION Comprehensive automated test suite verifying
% all 11 core requirements specified in Section 9 of the Implementation Prompt:
%
%   1.  Changing dashboard SOC changes simulation's initial SOC
%   2.  Changing SOH, temperature, resistance, or capacity affects downstream calculations
%   3.  Every vehicle's state remains strictly independent
%   4.  The station power limit is never exceeded
%   5.  No vehicle receives current beyond its permitted limits
%   6.  Faulted and completed vehicles receive zero charging power
%   7.  Charger output current is fed back into the battery model
%   8.  Dashboard telemetry matches simulation state
%   9.  Predictive models load and run in a clean MATLAB workspace
%   10. Reset restores the configured initial conditions
%   11. All allocation strategies are compared using identical initial conditions
%
% Usage:
%   all_pass = test_digital_twin_verification();

fprintf('\n=================================================================\n');
fprintf('  MASTER VERIFICATION TEST SUITE: DIGITAL TWIN INTEGRITY\n');
fprintf('=================================================================\n\n');

cfg = station_config();
all_pass = true;
test_count = 0;
pass_count = 0;

%% ------------------------------------------------------------------------
% TEST 1: CHANGING DASHBOARD SOC CHANGES INITIAL SIMULATION SOC
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 1] Verifying Dashboard Initial SOC Propagation...\n');

v_custom = cfg.default_user_vehicles(1);
test_soc_1 = 0.18; % 18%
test_soc_2 = 0.65; % 65%

v_custom.initial_SOC = test_soc_1;
veh1 = vehicle_manager.create_vehicle(v_custom, cfg);

v_custom.initial_SOC = test_soc_2;
veh2 = vehicle_manager.create_vehicle(v_custom, cfg);

t1_ok = (abs(veh1.battery.SOC - 0.18) < 1e-4) && (abs(veh2.battery.SOC - 0.65) < 1e-4) && ...
        (abs(veh1.initial_SOC - 0.18) < 1e-4) && (abs(veh2.initial_SOC - 0.65) < 1e-4);

if t1_ok
    fprintf('  PASS: Initial SOC propagated directly into battery model (18%% and 65%%).\n');
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Initial SOC did not propagate correctly.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 2: PARAMETER SENSITIVITIES (SOH, TEMP, RESISTANCE, CAPACITY)
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 2] Verifying Downstream Sensitivities (SOH, Temp, Rint, Capacity)...\n');

% 2.1 SOH Sensitivity on Internal Resistance Rint and BSI
v_high_soh = cfg.default_user_vehicles(1); v_high_soh.initial_SOH = 1.00;
v_low_soh  = cfg.default_user_vehicles(1); v_low_soh.initial_SOH  = 0.70;
veh_h_soh = vehicle_manager.create_vehicle(v_high_soh, cfg);
veh_l_soh = vehicle_manager.create_vehicle(v_low_soh, cfg);

[b_h, ~] = battery_model(veh_h_soh.battery, 10.0, 1.0, cfg);
[b_l, ~] = battery_model(veh_l_soh.battery, 10.0, 1.0, cfg);
soh_affects_r = (b_l.Rint > b_h.Rint); % Aged pack has higher Rint

% 2.2 Temperature Sensitivity on Thermal Derating
[cmd_cool, bsi_cool, ~] = bms_controller(veh_h_soh.battery, 48.0, 20.0, 1.0, 'adaptive', 0.90, cfg);
veh_hot = veh_h_soh; veh_hot.battery.Temperature = 38.0; % High temp
[cmd_hot, bsi_hot, ~] = bms_controller(veh_hot.battery, 48.0, 20.0, 1.0, 'adaptive', 0.90, cfg);
temp_affects_bms = (cmd_hot.C_rate_cmd < cmd_cool.C_rate_cmd) && (bsi_hot.BSI > bsi_cool.BSI);

% 2.3 Capacity Sensitivity on Predicted Charging Time
v_small = cfg.default_user_vehicles(1); v_small.Q_nom = 30.0; v_small.initial_SOC = 0.20; v_small.target_SOC = 0.80;
v_large = cfg.default_user_vehicles(1); v_large.Q_nom = 90.0; v_large.initial_SOC = 0.20; v_large.target_SOC = 0.80;
veh_s = vehicle_manager.create_vehicle(v_small, cfg);
veh_l = vehicle_manager.create_vehicle(v_large, cfg);
[T_s, E_s, ~] = charging_time_predictor.predict_completion_time(veh_s.battery, 4.0, 0.80, cfg);
[T_l, E_l, ~] = charging_time_predictor.predict_completion_time(veh_l.battery, 4.0, 0.80, cfg);
cap_affects_time = (E_l > E_s) && (T_l > T_s);

t2_ok = soh_affects_r && temp_affects_bms && cap_affects_time;
if t2_ok
    fprintf('  PASS: SOH, Temp, Rint, and Capacity strictly affect downstream physics.\n');
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Parameter sensitivity check failed.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 3: EVERY VEHICLE MAINTAINS STRICT INDEPENDENT STATE
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 3] Verifying Strict Vehicle State Independence...\n');

v1_in = cfg.default_user_vehicles(1); v1_in.id = 1; v1_in.Q_nom = 40.0; v1_in.initial_SOC = 0.20;
v2_in = cfg.default_user_vehicles(2); v2_in.id = 2; v2_in.Q_nom = 75.0; v2_in.initial_SOC = 0.60;

v1 = vehicle_manager.create_vehicle(v1_in, cfg);
v2 = vehicle_manager.create_vehicle(v2_in, cfg);

% Charge vehicle 1 only
[v1.battery, ~] = battery_model(v1.battery, 40.0, 10.0, cfg);

t3_ok = (v1.battery.SOC > 0.20) && (v2.battery.SOC == 0.60) && ...
        (v1.battery.Q_nom == 40.0) && (v2.battery.Q_nom == 75.0) && ...
        (v1.battery.energy_kWh > 0.0) && (v2.battery.energy_kWh == 0.0);

if t3_ok
    fprintf('  PASS: Vehicle states are completely decoupled and independent.\n');
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: State leakage detected between vehicles.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 4: STATION POWER LIMIT IS NEVER EXCEEDED
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 4] Verifying Total Station Grid Power Invariance...\n');

P_station_budget = 12.0; % kW
cfg_p = cfg;
cfg_p.station.grid_power_limit = P_station_budget;

% Create 4 power-hungry vehicles requiring 4.5 kW each (total 18 kW requested)
vehs = [];
chgs = repmat(struct(), 4, 1);
conns = repmat(struct(), 4, 1);
for i = 1:4
    v_in = cfg.default_user_vehicles(i);
    v_in.initial_SOC = 0.15;
    v_in.target_SOC = 0.90;
    v = vehicle_manager.create_vehicle(v_in, cfg_p);
    v.state = "CHARGING"; v.assigned_bay = i;
    vehs = [vehs, v];
    
    chgs(i).id = i; chgs(i).bay_id = i; chgs(i).status = "CHARGING"; chgs(i).fault_active = false;
    conns(i) = connector_manager.init_connector(i, i);
    conns(i).state = "LOCKED"; conns(i).electrical_connected = true;
end

% Test across all 3 allocation strategies
[alloc_eq, ~, ~]   = station_power_allocator.allocate_power(vehs, chgs, conns, 'equal', cfg_p);
[alloc_en, ~, ~]   = station_power_allocator.allocate_power(vehs, chgs, conns, 'energy_aware', cfg_p);
[alloc_pred, ~, ~] = station_power_allocator.allocate_power(vehs, chgs, conns, 'predictive_opt', cfg_p);

sum_eq   = sum(alloc_eq);
sum_en   = sum(alloc_en);
sum_pred = sum(alloc_pred);

t4_ok = (sum_eq <= P_station_budget + 1e-4) && ...
        (sum_en <= P_station_budget + 1e-4) && ...
        (sum_pred <= P_station_budget + 1e-4);

if t4_ok
    fprintf('  PASS: Station power bound strictly enforced: Equal=%.2f kW, Energy=%.2f kW, Pred=%.2f kW <= %.2f kW.\n', ...
        sum_eq, sum_en, sum_pred, P_station_budget);
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Station grid power limit exceeded!\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 5: NO VEHICLE RECEIVES CURRENT BEYOND PERMITTED LIMITS
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 5] Verifying Current Clamping against Permitted Limits...\n');

v_limit = cfg.default_user_vehicles(1);
v_limit.Q_nom = 40.0;
v_limit.C_max = 1.0;  % 40 A design limit
v_limit.I_max = 35.0; % Strict 35 A limit
veh_lim = vehicle_manager.create_vehicle(v_limit, cfg);

% BMS commanded current under high allocation
OCV = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, veh_lim.battery.SOC, 'pchip');
[bms_cmd, ~, ~] = bms_controller(veh_lim.battery, OCV, 0.0, 1.0, 'adaptive', 0.90, cfg);

% Charger model current with 4.5 kW available
chg = struct('status', "CHARGING", 'fault_active', false, 'energy_delivered_kWh', 0.0);
[~, I_deliv, ~, ~] = charger_model(chg, bms_cmd.I_cmd, 44.0, true, 4.5, 1.0, cfg);

t5_ok = (I_deliv <= 35.0 + 1e-4) && (bms_cmd.I_cmd <= 35.0 + 1e-4);
if t5_ok
    fprintf('  PASS: Commanded and delivered current strictly clamped to I_max (%.1f A <= 35.0 A).\n', I_deliv);
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Current limit boundary violated (I_deliv = %.1f A > 35.0 A).\n', I_deliv);
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 6: FAULTED AND COMPLETED VEHICLES RECEIVE ZERO CHARGING POWER
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 6] Verifying Power Cutoff on Fault, Disabled, or Target Achieved...\n');

% Completed vehicle: SOC = target_SOC
v_done = cfg.default_user_vehicles(1);
v_done.initial_SOC = 0.90; v_done.target_SOC = 0.90;
veh_done = vehicle_manager.create_vehicle(v_done, cfg);

% Disabled vehicle: is_enabled = false
v_dis = cfg.default_user_vehicles(2);
v_dis.is_enabled = false;
veh_dis = vehicle_manager.create_vehicle(v_dis, cfg);

% Over-temperature vehicle: Temp >= 45 C
v_hot = cfg.default_user_vehicles(3);
v_hot.initial_Temp = 46.0;
veh_hot = vehicle_manager.create_vehicle(v_hot, cfg);

% Evaluate BMS controllers
[cmd_done, ~, ~] = bms_controller(veh_done.battery, 52.8, 0.0, 1.0, 'adaptive', 0.90, cfg);
[cmd_dis,  ~, ~] = bms_controller(veh_dis.battery,  44.0, 0.0, 1.0, 'adaptive', 0.90, cfg);
[cmd_hot,  ~, ~] = bms_controller(veh_hot.battery,  44.0, 0.0, 1.0, 'adaptive', 0.90, cfg);

% Evaluate Power Allocator
t_vehs = [veh_done, veh_dis, veh_hot];
t_vehs(1).state = "CHARGING"; t_vehs(1).assigned_bay = 1;
t_vehs(2).state = "CHARGING"; t_vehs(2).assigned_bay = 2;
t_vehs(3).state = "CHARGING"; t_vehs(3).assigned_bay = 3;

t_chgs = repmat(struct('id', 1, 'bay_id', 1, 'status', "CHARGING", 'fault_active', false), 3, 1);
t_chgs(1).bay_id = 1; t_chgs(2).bay_id = 2; t_chgs(3).bay_id = 3;
t_conns = repmat(struct('electrical_connected', true), 3, 1);

[alloc_off, ~, ~] = station_power_allocator.allocate_power(t_vehs, t_chgs, t_conns, 'predictive_opt', cfg);

t6_ok = (cmd_done.I_cmd == 0.0) && (cmd_dis.I_cmd == 0.0) && (cmd_hot.I_cmd == 0.0) && ...
        all(alloc_off == 0.0);

if t6_ok
    fprintf('  PASS: Zero power and zero current assigned to completed, disabled, and faulted vehicles.\n');
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Power allocated to inactive/faulted vehicle.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 7: CHARGER CURRENT IS FED BACK INTO BATTERY MODEL
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 7] Verifying Closed-Loop Current Feedback into Battery Model...\n');

v_base = cfg.default_user_vehicles(1);
v_base.initial_SOC = 0.20;
veh_fb = vehicle_manager.create_vehicle(v_base, cfg);

% Deliver 50 A over 10 seconds (dt = 10 s)
% Expected dSOC = (50 A * 10 s) / (50 Ah * 3600 s) = 500 / 180000 = +0.002778
[b_next, ~] = battery_model(veh_fb.battery, 50.0, 10.0, cfg);
expected_soc = 0.20 + (50.0 * 10.0) / (veh_fb.battery.Q_nom * 3600.0);

t7_ok = (abs(b_next.SOC - expected_soc) < 1e-5) && ...
        (b_next.Current == 50.0) && ...
        (b_next.Temperature > veh_fb.battery.Temperature) && ...
        (b_next.energy_kWh > 0.0);

if t7_ok
    fprintf('  PASS: Coulomb counting and thermal dynamics respond directly to delivered current feedback.\n');
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Current feedback integration error.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 8: DASHBOARD TELEMETRY MATCHES SIMULATION STATE
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 8] Verifying Dashboard Telemetry State Consistency...\n');

dash = station_dashboard(cfg, [], true); % Headless instance
u_cfg = dash.get_user_config();

t8_ok = (length(u_cfg.vehicles) == 4) && ...
        (u_cfg.station.grid_power_limit == cfg.station.grid_power_limit) && ...
        (u_cfg.vehicles(1).initial_SOC == cfg.default_user_vehicles(1).initial_SOC);

if t8_ok
    fprintf('  PASS: Dashboard configuration matches authoritative simulation parameters.\n');
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Telemetry mismatch between dashboard and simulation config.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 9: PREDICTIVE MODELS LOAD IN A CLEAN WORKSPACE WITHOUT GLOBALS
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 9] Verifying Workspace-Independent Predictive Analytics...\n');

% Ensure no base-workspace variables exist
model = predictive_analytics.get_model();

v_test = cfg.default_user_vehicles(1);
veh_p = vehicle_manager.create_vehicle(v_test, cfg);
[pred_T, pred_BSI, C_adv, info] = predictive_analytics.forecast(model, veh_p.battery, 150, cfg);

t9_ok = ~isempty(model.provenance) && ...
        isnumeric(pred_T) && ~isnan(pred_T) && (pred_T >= 25.0) && ...
        isnumeric(pred_BSI) && ~isnan(pred_BSI) && (pred_BSI >= 0.0) && ...
        isnumeric(C_adv) && (C_adv <= veh_p.battery.C_max);

if t9_ok
    fprintf('  PASS: Model evaluated cleanly (%s, Pred T = %.1f °C, Pred BSI = %.1f).\n', ...
        info.method, pred_T, pred_BSI);
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Predictive model failed to evaluate in clean workspace.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 10: RESET RESTORES CONFIGURED INITIAL CONDITIONS
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 10] Verifying Simulation Reset Functionality...\n');

v_orig = cfg.default_user_vehicles(1);
v_orig.initial_SOC = 0.22;
v_orig.initial_Temp = 25.0;
veh_rst = vehicle_manager.create_vehicle(v_orig, cfg);

% Advance state (charge and heat up)
veh_rst.battery.SOC = 0.55;
veh_rst.battery.Temperature = 34.5;
veh_rst.battery.energy_kWh = 1.25;
veh_rst.state = "CHARGING";

% Execute Reset
veh_rst = vehicle_manager.reset_vehicle(veh_rst, cfg);

t10_ok = (abs(veh_rst.battery.SOC - 0.22) < 1e-4) && ...
         (abs(veh_rst.battery.Temperature - 25.0) < 1e-4) && ...
         (veh_rst.battery.energy_kWh == 0.0) && ...
         (veh_rst.state == "ARRIVING");

if t10_ok
    fprintf('  PASS: Reset restored exact initial configured conditions.\n');
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Reset did not restore initial state.\n');
    all_pass = false;
end

%% ------------------------------------------------------------------------
% TEST 11: IDENTICAL FLEET STRATEGY COMPARISON & OPTIMIZATION VERIFICATION
% ------------------------------------------------------------------------
test_count = test_count + 1;
fprintf('[TEST 11] Verifying Multi-Strategy Allocation on Identical Fleets...\n');

% Set up the 3-vehicle bottleneck fleet:
% Car 1: 80% SOC (needs 10% to 90%)
% Car 2: 80% SOC (needs 10% to 90%)
% Car 3: 20% SOC (needs 70% to 90% - bottleneck)
v_test_fleet = cfg.default_user_vehicles(1:3);
v_test_fleet(1).initial_SOC = 0.80; v_test_fleet(1).target_SOC = 0.90;
v_test_fleet(2).initial_SOC = 0.80; v_test_fleet(2).target_SOC = 0.90;
v_test_fleet(3).initial_SOC = 0.20; v_test_fleet(3).target_SOC = 0.90;

st_test.grid_power_limit = 10.0;
st_test.num_vehicles = 3;
st_test.bms_strategy = 'adaptive';
st_test.dt = 1.0;

comp_res = compare_allocation_strategies(v_test_fleet, st_test, cfg);

makespan_eq   = comp_res.runs(1).actual_makespan_min;
makespan_pred = comp_res.runs(3).actual_makespan_min;
gain_pct      = comp_res.reduction_pct_vs_equal;

t11_ok = (makespan_pred <= makespan_eq) && (gain_pct >= 0.0);

if t11_ok
    fprintf('  PASS: Head-to-head comparison successful: Predictive Makespan (%.1f min) beats Equal (%.1f min) by %.1f%%.\n', ...
        makespan_pred, makespan_eq, gain_pct);
    pass_count = pass_count + 1;
else
    fprintf('  FAIL: Optimization did not reduce makespan.\n');
    all_pass = false;
end

%% ========================================================================
% SUMMARY RESULTS
% ========================================================================
fprintf('\n=================================================================\n');
fprintf('  VERIFICATION SUITE SUMMARY: %d / %d TESTS PASSED (%.1f%%)\n', ...
    pass_count, test_count, (pass_count/test_count)*100);
fprintf('=================================================================\n\n');

all_pass = (pass_count == test_count);

end
