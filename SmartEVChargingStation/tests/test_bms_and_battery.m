function pass = test_bms_and_battery()
% TEST_BMS_AND_BATTERY Verification test script for battery physical model,
% BSI engine, and multi-stage adaptive controller.

fprintf('=== RUNNING TEST SUITE: BMS & BATTERY PHYSICAL INTEGRITY ===\n');
cfg = station_config();
pass = true;

%% Test 1: Battery OCV and Resistance Model at 20% SOC
SOC_test = 0.20;
OCV_expected = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, SOC_test, 'pchip');

state.SOC = SOC_test;
state.SOH = 0.95;
state.Temperature = 25.0;
state.Q_nom = 50.0;
state.R_initial = 0.050;
state.C_max = 1.5;
state.energy_kWh = 0.0;

[state_next, OCV_calc] = battery_model(state, 0.0, 1.0, cfg);

if abs(OCV_calc - 42.8) < 0.1
    fprintf('[PASS] Test 1.1: OCV Lookup at 20%% SOC = %.2f V (Matches reference)\n', OCV_calc);
else
    fprintf('[FAIL] Test 1.1: OCV Lookup mismatch: %.2f V\n', OCV_calc);
    pass = false;
end

if state_next.Rint > 0.050 && state_next.Rint < 0.070
    fprintf('[PASS] Test 1.2: Internal Resistance Rint = %.4f Ohm (Plausible Li-ion range)\n', state_next.Rint);
else
    fprintf('[FAIL] Test 1.2: Rint out of expected range: %.4f Ohm\n', state_next.Rint);
    pass = false;
end

%% Test 2: Coulomb Counting Numerical Consistency
I_charge = 50.0; % 1C current for 50Ah battery
dt = 36.0;       % 36 seconds = 0.01 hours
[state_step, ~] = battery_model(state, I_charge, dt, cfg);

% Expected dSOC = (50 * 36) / (50 * 3600) = 0.01 (1% SOC increase)
expected_SOC = 0.21;
if abs(state_step.SOC - expected_SOC) < 1.0e-5
    fprintf('[PASS] Test 2.1: Coulomb Counting SOC Integration: %.4f -> %.4f (Exact match)\n', state.SOC, state_step.SOC);
else
    fprintf('[FAIL] Test 2.1: Coulomb Counting error: Expected %.4f, Got %.4f\n', expected_SOC, state_step.SOC);
    pass = false;
end

%% Test 3: Thermal Lumped Capacitance Dynamics
% Over 36 seconds with 50A current, heat generation P = I^2*R = 2500 * 0.0616 = ~154 W
% Net dT = (154 - 0) / 40000 * 36 = ~0.138 deg C
expected_dT = ( (I_charge^2 * state_step.Rint) / cfg.battery.Cth ) * dt;
actual_dT = state_step.Temperature - state.Temperature;

if abs(actual_dT - expected_dT) < 0.01 && actual_dT > 0
    fprintf('[PASS] Test 3.1: Thermal Model Heating: dT = +%.4f °C over %ds (Physically consistent)\n', actual_dT, dt);
else
    fprintf('[FAIL] Test 3.1: Thermal heating error: Expected %.4f, Got %.4f\n', expected_dT, actual_dT);
    pass = false;
end

%% Test 4: BSI Evaluation and Normalization
[bms_cmd, bsi_data, fault] = bms_controller(state_step, OCV_calc, I_charge, 1.0, 'adaptive', 0.90, cfg);

if bsi_data.BSI >= 0.0 && bsi_data.BSI <= 100.0
    fprintf('[PASS] Test 4.1: Battery Stress Index Normalized: BSI = %.2f / 100\n', bsi_data.BSI);
else
    fprintf('[FAIL] Test 4.1: BSI out of bounds [0, 100]: %.2f\n', bsi_data.BSI);
    pass = false;
end

%% Test 5: Over-Temperature Fault Shutdown
state_hot = state_step;
state_hot.Temperature = 45.5; % Above 45 deg C trip threshold
[cmd_trip, ~, fault_trip] = bms_controller(state_hot, OCV_calc, I_charge, 1.0, 'adaptive', 0.90, cfg);

if fault_trip.active && cmd_trip.I_cmd == 0.0
    fprintf('[PASS] Test 5.1: Over-Temperature Trip Interlock: Current shut off to 0A (%s)\n', fault_trip.msg);
else
    fprintf('[FAIL] Test 5.1: Safety interlock failed to trip on T=%.1f C\n', state_hot.Temperature);
    pass = false;
end

%% Final Summary
if pass
    fprintf('\n>>> ALL BMS & BATTERY TESTS PASSED SUCCESSFULLY! <<<\n\n');
else
    fprintf('\n>>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<\n\n');
end

end
