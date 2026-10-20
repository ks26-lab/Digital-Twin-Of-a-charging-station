function pass = test_charging_time()
% TEST_CHARGING_TIME Validates the non-linear charging completion time
% predictor against physical battery model dynamics and CC-CV transitions.

fprintf('=== RUNNING TEST SUITE: CHARGING TIME PREDICTOR ===\n');
cfg = station_config();
pass = true;

%% Test 1: Zero Time for Fully Charged Battery
bat.SOC = 0.90;
bat.Q_nom = 50.0;
bat.Rint = 0.050;
bat.C_max = 1.5;

[T_pred, E_rem, ~] = charging_time_predictor.predict_completion_time(bat, 3.5, 0.90, cfg);
if T_pred == 0.0 && E_rem == 0.0
    fprintf('[PASS] Test 1: Zero time and zero energy remaining when SOC >= target_SOC\n');
else
    fprintf('[FAIL] Test 1: Expected 0s, got %.2fs\n', T_pred);
    pass = false;
end

%% Test 2: CC-Phase Charging Duration
% 20% to 50% SOC at 1C (50A, approx 2.4 kW DC power)
% dSOC = 0.30. Q = 50 Ah. Expected time = (0.30 * 50 * 3600) / 50 = 1080 seconds (18.0 min)
bat_cc.SOC = 0.20;
bat_cc.Q_nom = 50.0;
bat_cc.Rint = 0.050;
bat_cc.C_max = 1.5;

P_test_kW = 2.4; % 2.4 kW at ~48V gives ~50A current
[T_cc_pred, E_rem_cc, ~] = charging_time_predictor.predict_completion_time(bat_cc, P_test_kW, 0.50, cfg);

expected_cc_min = 18.0;
actual_cc_min   = T_cc_pred / 60.0;
if abs(actual_cc_min - expected_cc_min) < 2.0
    fprintf('[PASS] Test 2: CC-phase duration: Predicted = %.1f min (Matches analytical ~%.1f min)\n', actual_cc_min, expected_cc_min);
else
    fprintf('[FAIL] Test 2: CC-phase prediction error: Expected ~%.1f min, got %.1f min\n', expected_cc_min, actual_cc_min);
    pass = false;
end

%% Test 3: CV-Phase Current Tapering Slowdown
% 70% to 90% SOC enters CV tapering region. Should take strictly longer than pure CC calculation
bat_cv.SOC = 0.70;
bat_cv.Q_nom = 50.0;
bat_cv.Rint = 0.055;
bat_cv.C_max = 1.5;

[T_cv_pred, E_rem_cv, ~] = charging_time_predictor.predict_completion_time(bat_cv, 4.0, 0.90, cfg);
% Pure unconstrained CC at 4kW would take: (0.20 * 50 * 3600) / (4000/50) = 450s = 7.5 min
% With CV taper, it must take > 9.0 min
if T_cv_pred > 500
    fprintf('[PASS] Test 3: CV-phase tapering accounted for: Predicted = %.1f min (> pure CC rate)\n', T_cv_pred/60);
else
    fprintf('[FAIL] Test 3: CV tapering not properly reflected: %.1fs\n', T_cv_pred);
    pass = false;
end

%% Test 4: Inverse Model Consistency (calculate_power_for_target_time)
% Request power to finish charging 20% -> 90% in exactly 45 minutes (2700 seconds)
target_t_sec = 2700;
P_inferred = charging_time_predictor.calculate_power_for_target_time(bat_cc, target_t_sec, 0.90, cfg);

% Verify back through predictor
T_back_sec = charging_time_predictor.predict_completion_time(bat_cc, P_inferred, 0.90, cfg);
error_pct  = abs(T_back_sec - target_t_sec) / target_t_sec * 100.0;

if error_pct < 15.0 && P_inferred > 0
    fprintf('[PASS] Test 4: Inverse power model consistency: Target = %.1f min, Predicted = %.1f min (Error = %.1f%%)\n', ...
        target_t_sec/60, T_back_sec/60, error_pct);
else
    fprintf('[FAIL] Test 4: Inversion error: Target = %.1f min, Predicted = %.1f min (Error = %.1f%%)\n', ...
        target_t_sec/60, T_back_sec/60, error_pct);
    pass = false;
end

%% Final Summary
if pass
    fprintf('\n>>> ALL CHARGING TIME PREDICTOR TESTS PASSED! <<<\n\n');
else
    fprintf('\n>>> SOME TESTS FAILED! <<<\n\n');
end

end
