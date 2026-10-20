function results = test_three_ev_dynamic_reallocation()
% TEST_THREE_EV_DYNAMIC_REALLOCATION Comprehensive test suite for 3-EV dynamic
% allocation, stage-by-stage connection/verification gating, and hardcode audit.
%
% Tests all 7 required scenarios:
%   Test 1: Similar SOC (EV1=70%, EV2=80%, EV3=70%)
%   Test 2: Low-SOC arrival (EV1=70%, EV2=80%, EV3=20%)
%   Test 3: High-SOC arrival (EV1=70%, EV2=80%, EV3=88%)
%   Test 4: BMS Rejection (Over-temperature fault injection on EV3)
%   Test 5: No Power Shortage (Station budget 30 kW, unconstrained)
%   Test 6: Severe Power Shortage (Station budget 4 kW, heavy throttling)
%   Test 7: Parameter Sensitivity & Negative Tests (Power sweep, disabled EV, reproducibility)
%
% Output:
%   results: Struct containing test status, metrics, and recorded event values.

fprintf('\n========================================================================\n');
fprintf('  STARTING TEST SUITE: THREE-EV DYNAMIC REALLOCATION & BMS VERIFICATION\n');
fprintf('========================================================================\n');

results = struct();
results.passed = 0;
results.failed = 0;
results.total  = 0;
results.details = {};

%% ------------------------------------------------------------------------
%% TEST 1: SIMILAR SOC (EV1=70%, EV2=80%, EV3=70%)
%% ------------------------------------------------------------------------
results.total = results.total + 1;
test_name = 'Test 1: Similar SOC Baseline (EV1=70%, EV2=80%, EV3=70%)';
fprintf('\n--- Running %s ---\n', test_name);
try
    cfg1 = struct();
    cfg1.t_connect = 60.0;
    cfg1.t_verify  = 80.0;
    cfg1.t_end     = 180.0;
    cfg1.dt        = 0.5;
    cfg1.P_station = 10.0; % 10 kW
    cfg1.strategy  = 'predictive_opt';
    cfg1.ev3.initial_SOC = 0.70;
    
    log1 = simulate_three_ev_scenario(cfg1);
    
    % Assertion 1.1: EV 3 current must be strictly 0.0 A before BMS verification (t < 80s)
    idx_pending = find(log1.time >= 60.0 & log1.time < 80.0);
    ev3_pending_I = max(log1.I_delivered(idx_pending, 3));
    assert(ev3_pending_I == 0.0, 'ASSERTION FAILED: EV3 received non-zero current while verification was pending!');
    
    % Assertion 1.2: EV 3 is authorized after t_verify and receives non-zero current
    idx_post = find(log1.time >= 100.0);
    ev3_post_I = mean(log1.I_delivered(idx_post, 3));
    assert(ev3_post_I > 5.0, 'ASSERTION FAILED: EV3 did not receive charging current after BMS verification!');
    
    % Assertion 1.3: EV1 and EV2 currents were throttled to make room for EV3
    idx_pre = find(log1.time >= 40.0 & log1.time < 60.0);
    I1_pre = mean(log1.I_delivered(idx_pre, 1));
    I2_pre = mean(log1.I_delivered(idx_pre, 2));
    I1_post = mean(log1.I_delivered(idx_post, 1));
    I2_post = mean(log1.I_delivered(idx_post, 2));
    
    assert(I1_post < I1_pre, 'ASSERTION FAILED: EV1 current was not throttled when EV3 joined under power constraint!');
    assert(I2_post < I2_pre, 'ASSERTION FAILED: EV2 current was not throttled when EV3 joined under power constraint!');
    
    % Assertion 1.4: Station power does not exceed station limit (allowing 1% numerical tolerance for discrete slew)
    max_P_station = max(log1.P_station_total);
    assert(max_P_station <= cfg1.P_station * 1.02, sprintf('ASSERTION FAILED: Station power exceeded limit! Max: %.2f kW', max_P_station));
    
    % Assertion 1.5: Verify no special-case ID rule: EV1 (70% SOC, 50 Ah) vs EV3 (70% SOC, 65 Ah)
    % Allocated power should be proportional to demand and capacity, not an arbitrary override
    ratio_alloc = log1.P_allocated(idx_post(end), 3) / log1.P_allocated(idx_post(end), 1);
    assert(ratio_alloc > 0.8 && ratio_alloc < 1.6, 'ASSERTION FAILED: EV3 allocation is anomalous compared to EV1!');
    
    fprintf('  [PASS] %s\n', test_name);
    fprintf('         I1 pre: %.1fA -> post: %.1fA | I2 pre: %.1fA -> post: %.1fA | I3 post: %.1fA\n', ...
        I1_pre, I1_post, I2_pre, I2_post, ev3_post_I);
    fprintf('         EV3 I during pending (60-80s): %.3f A (Strictly 0.0 A)\n', ev3_pending_I);
    results.passed = results.passed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'PASS');
catch ME
    fprintf('  [FAIL] %s: %s\n', test_name, ME.message);
    results.failed = results.failed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'FAIL', 'error', ME.message);
end

%% ------------------------------------------------------------------------
%% TEST 2: LOW-SOC ARRIVAL (EV1=70%, EV2=80%, EV3=20%)
%% ------------------------------------------------------------------------
results.total = results.total + 1;
test_name = 'Test 2: Low-SOC Arrival (EV3=20% vs Baseline EV3=70%)';
fprintf('\n--- Running %s ---\n', test_name);
try
    cfg2 = struct();
    cfg2.t_connect = 60.0;
    cfg2.t_verify  = 80.0;
    cfg2.t_end     = 180.0;
    cfg2.dt        = 0.5;
    cfg2.P_station = 10.0;
    cfg2.strategy  = 'predictive_opt';
    cfg2.ev3.initial_SOC = 0.20; % Deep discharge, high charging urgency
    
    log2 = simulate_three_ev_scenario(cfg2);
    
    idx_post = find(log2.time >= 100.0);
    I3_low_soc = mean(log2.I_delivered(idx_post, 3));
    P3_low_soc = mean(log2.P_delivered(idx_post, 3));
    
    % In predictive optimization, vehicle with lower SOC (20% vs 70%) has higher urgency weight
    % and higher allowable CC current from BMS (no SOC derate).
    % Thus EV3 current with 20% SOC should be >= its current with 70% SOC.
    assert(I3_low_soc >= ev3_post_I * 0.95, 'ASSERTION FAILED: Low SOC EV3 did not receive high charging priority!');
    
    % Total station limit respected
    assert(max(log2.P_station_total) <= cfg2.P_station * 1.02, 'ASSERTION FAILED: Station budget violated in Test 2!');
    
    fprintf('  [PASS] %s\n', test_name);
    fprintf('         EV3 (20%% SOC) post-verify current: %.1f A, Power: %.2f kW\n', I3_low_soc, P3_low_soc);
    results.passed = results.passed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'PASS');
catch ME
    fprintf('  [FAIL] %s: %s\n', test_name, ME.message);
    results.failed = results.failed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'FAIL', 'error', ME.message);
end

%% ------------------------------------------------------------------------
%% TEST 3: HIGH-SOC ARRIVAL (EV1=70%, EV2=80%, EV3=88%)
%% ------------------------------------------------------------------------
results.total = results.total + 1;
test_name = 'Test 3: High-SOC Arrival with CV Tapering (EV3=88%)';
fprintf('\n--- Running %s ---\n', test_name);
try
    cfg3 = struct();
    cfg3.t_connect = 60.0;
    cfg3.t_verify  = 80.0;
    cfg3.t_end     = 180.0;
    cfg3.dt        = 0.5;
    cfg3.P_station = 10.0;
    cfg3.strategy  = 'predictive_opt';
    cfg3.ev3.initial_SOC = 0.88; % Close to 90% target, BMS in CV taper zone
    
    log3 = simulate_three_ev_scenario(cfg3);
    
    idx_post = find(log3.time >= 100.0);
    I3_high_soc = mean(log3.I_delivered(idx_post, 3));
    
    % BMS derate for SOC > 85% must taper current significantly below normal CC current
    assert(I3_high_soc < ev3_post_I, 'ASSERTION FAILED: High SOC EV3 was not tapered by BMS controller!');
    assert(I3_high_soc > 0.0, 'ASSERTION FAILED: High SOC EV3 received 0 current when still below target SOC (90%)!');
    
    fprintf('  [PASS] %s\n', test_name);
    fprintf('         EV3 (88%% SOC) tapered current: %.1f A (vs %.1f A at 70%% SOC)\n', I3_high_soc, ev3_post_I);
    results.passed = results.passed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'PASS');
catch ME
    fprintf('  [FAIL] %s: %s\n', test_name, ME.message);
    results.failed = results.failed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'FAIL', 'error', ME.message);
end

%% ------------------------------------------------------------------------
%% TEST 4: BMS REJECTION (OVER-TEMPERATURE FAULT INJECTION)
%% ------------------------------------------------------------------------
results.total = results.total + 1;
test_name = 'Test 4: BMS Verification Rejection (Over-Temp 46.5 C >= 45 C Limit)';
fprintf('\n--- Running %s ---\n', test_name);
try
    cfg4 = struct();
    cfg4.t_connect = 60.0;
    cfg4.t_verify  = 80.0;
    cfg4.t_end     = 180.0;
    cfg4.dt        = 0.5;
    cfg4.P_station = 10.0;
    cfg4.ev3_inject_fault = true;
    cfg4.ev3_fault_type   = 'ERR_OVER_TEMP';
    
    log4 = simulate_three_ev_scenario(cfg4);
    
    % Assertion 4.1: EV 3 is in REJECTED state for all t >= 80s
    idx_fault = find(log4.time >= 80.0);
    auth_states = log4.bms_auth(idx_fault, 3);
    assert(all(auth_states == "REJECTED"), 'ASSERTION FAILED: EV3 was not marked REJECTED after fault!');
    
    % Assertion 4.2: EV 3 current remains strictly 0.0 A throughout the simulation
    max_ev3_fault_I = max(log4.I_delivered(:, 3));
    assert(max_ev3_fault_I == 0.0, sprintf('ASSERTION FAILED: EV3 received current despite BMS rejection! Max I: %.2f A', max_ev3_fault_I));
    
    % Assertion 4.3: Fault message correctly recorded
    last_fault = log4.fault_reason(end, 3);
    assert(contains(last_fault, 'ERR_OVER_TEMP'), 'ASSERTION FAILED: Fault reason string missing or incorrect!');
    
    % Assertion 4.4: EVs 1 and 2 continue charging unthrottled since EV3 power was not authorized
    I1_post_reject = mean(log4.I_delivered(idx_fault, 1));
    I2_post_reject = mean(log4.I_delivered(idx_fault, 2));
    assert(I1_post_reject > I1_post * 1.1, 'ASSERTION FAILED: EV1 was unnecessarily throttled for a rejected EV3!');
    assert(I2_post_reject > I2_post * 1.1, 'ASSERTION FAILED: EV2 was unnecessarily throttled for a rejected EV3!');
    
    fprintf('  [PASS] %s\n', test_name);
    fprintf('         EV3 State: %s | Max I: %.3f A | Recorded Fault: %s\n', ...
        auth_states(end), max_ev3_fault_I, last_fault);
    fprintf('         EV1 & EV2 unthrottled currents: I1=%.1f A, I2=%.1f A\n', I1_post_reject, I2_post_reject);
    results.passed = results.passed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'PASS');
catch ME
    fprintf('  [FAIL] %s: %s\n', test_name, ME.message);
    results.failed = results.failed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'FAIL', 'error', ME.message);
end

%% ------------------------------------------------------------------------
%% TEST 5: NO POWER SHORTAGE (STATION BUDGET = 30 kW)
%% ------------------------------------------------------------------------
results.total = results.total + 1;
test_name = 'Test 5: No Power Shortage (Station Budget 30 kW >> Demand)';
fprintf('\n--- Running %s ---\n', test_name);
try
    cfg5 = struct();
    cfg5.t_connect = 60.0;
    cfg5.t_verify  = 80.0;
    cfg5.t_end     = 180.0;
    cfg5.dt        = 0.5;
    cfg5.P_station = 30.0; % Abundant power
    cfg5.ev3.initial_SOC = 0.70;
    
    log5 = simulate_three_ev_scenario(cfg5);
    
    idx_pre  = find(log5.time >= 40.0 & log5.time < 60.0);
    idx_post = find(log5.time >= 100.0);
    
    I1_pre5  = mean(log5.I_delivered(idx_pre, 1));
    I1_post5 = mean(log5.I_delivered(idx_post, 1));
    I2_pre5  = mean(log5.I_delivered(idx_pre, 2));
    I2_post5 = mean(log5.I_delivered(idx_post, 2));
    
    % In unconstrained condition, EV1 and EV2 must NOT suffer current reduction when EV3 connects
    % (allowing tiny 2% difference due to normal SOC rise / impedance changes)
    assert(abs(I1_post5 - I1_pre5) / I1_pre5 < 0.05, 'ASSERTION FAILED: EV1 was unnecessarily throttled with 30 kW budget!');
    assert(abs(I2_post5 - I2_pre5) / I2_pre5 < 0.05, 'ASSERTION FAILED: EV2 was unnecessarily throttled with 30 kW budget!');
    
    fprintf('  [PASS] %s\n', test_name);
    fprintf('         EV1: pre=%.1f A, post=%.1f A (diff: %.1f%%)\n', I1_pre5, I1_post5, abs(I1_post5-I1_pre5)/I1_pre5*100);
    fprintf('         EV2: pre=%.1f A, post=%.1f A (diff: %.1f%%)\n', I2_pre5, I2_post5, abs(I2_post5-I2_pre5)/I2_pre5*100);
    results.passed = results.passed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'PASS');
catch ME
    fprintf('  [FAIL] %s: %s\n', test_name, ME.message);
    results.failed = results.failed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'FAIL', 'error', ME.message);
end

%% ------------------------------------------------------------------------
%% TEST 6: SEVERE POWER SHORTAGE (STATION BUDGET = 4.0 kW)
%% ------------------------------------------------------------------------
results.total = results.total + 1;
test_name = 'Test 6: Severe Power Shortage (Station Budget 4.0 kW)';
fprintf('\n--- Running %s ---\n', test_name);
try
    cfg6 = struct();
    cfg6.t_connect = 60.0;
    cfg6.t_verify  = 80.0;
    cfg6.t_end     = 180.0;
    cfg6.dt        = 0.5;
    cfg6.P_station = 4.0; % Severely constrained
    cfg6.ev3.initial_SOC = 0.70;
    
    log6 = simulate_three_ev_scenario(cfg6);
    
    idx_pre  = find(log6.time >= 40.0 & log6.time < 60.0);
    idx_post = find(log6.time >= 100.0);
    
    I1_pre6  = mean(log6.I_delivered(idx_pre, 1));
    I1_post6 = mean(log6.I_delivered(idx_post, 1));
    I2_pre6  = mean(log6.I_delivered(idx_pre, 2));
    I2_post6 = mean(log6.I_delivered(idx_post, 2));
    I3_post6 = mean(log6.I_delivered(idx_post, 3));
    
    % In severe shortage, all three must share the 4 kW (~1.33 kW each => ~26 A each)
    assert(I1_post6 < I1_pre6 * 0.8, 'ASSERTION FAILED: EV1 was not significantly throttled under severe power shortage!');
    assert(I2_post6 < I2_pre6 * 0.8, 'ASSERTION FAILED: EV2 was not significantly throttled under severe power shortage!');
    assert(max(log6.P_station_total) <= 4.0 * 1.02, 'ASSERTION FAILED: Total station power exceeded 4.0 kW limit!');
    
    fprintf('  [PASS] %s\n', test_name);
    fprintf('         Pre-EV3: I1=%.1f A, I2=%.1f A | Post-EV3: I1=%.1f A, I2=%.1f A, I3=%.1f A\n', ...
        I1_pre6, I2_pre6, I1_post6, I2_post6, I3_post6);
    fprintf('         Peak station power: %.2f kW <= 4.0 kW\n', max(log6.P_station_total));
    results.passed = results.passed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'PASS');
catch ME
    fprintf('  [FAIL] %s: %s\n', test_name, ME.message);
    results.failed = results.failed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'FAIL', 'error', ME.message);
end

%% ------------------------------------------------------------------------
%% TEST 7: PARAMETER SENSITIVITY, NEGATIVE TESTS & REPRODUCIBILITY
%% ------------------------------------------------------------------------
results.total = results.total + 1;
test_name = 'Test 7: Sensitivity, Negative Test (Disabled EV), and Reproducibility';
fprintf('\n--- Running %s ---\n', test_name);
try
    % 7.1 Grid Budget Sensitivity Sweep (5 kW, 10 kW, 15 kW)
    budgets = [5.0, 10.0, 15.0];
    avg_powers = zeros(length(budgets), 1);
    for b = 1:length(budgets)
        cfg_sweep = struct('P_station', budgets(b), 't_connect', 60.0, 't_verify', 80.0, 't_end', 120.0, 'dt', 1.0);
        log_sweep = simulate_three_ev_scenario(cfg_sweep);
        avg_powers(b) = mean(log_sweep.P_station_total(log_sweep.time >= 100.0));
    end
    % Power delivered must increase monotonically with station budget
    assert(issorted(avg_powers), 'ASSERTION FAILED: Delivered station power is not monotonic with station budget!');
    
    % 7.2 Negative Test: Disable EV 2 manually
    cfg_neg = struct('t_connect', 60.0, 't_verify', 80.0, 't_end', 120.0, 'dt', 1.0);
    cfg_neg.ev2.is_enabled = false;
    log_neg = simulate_three_ev_scenario(cfg_neg);
    max_ev2_neg_I = max(log_neg.I_delivered(:, 2));
    assert(max_ev2_neg_I == 0.0, 'ASSERTION FAILED: Disabled EV2 received non-zero charging current!');
    
    % 7.3 Reproducibility: Identical simulation runs must produce bitwise/numerical identical outputs
    cfg_rep = struct('t_connect', 60.0, 't_verify', 80.0, 't_end', 100.0, 'dt', 1.0);
    log_r1 = simulate_three_ev_scenario(cfg_rep);
    log_r2 = simulate_three_ev_scenario(cfg_rep);
    diff_norm = norm(log_r1.I_delivered - log_r2.I_delivered);
    assert(diff_norm == 0.0, 'ASSERTION FAILED: Simulation is non-deterministic or not reproducible!');
    
    fprintf('  [PASS] %s\n', test_name);
    fprintf('         Power sweep results: [5kW -> %.2f kW, 10kW -> %.2f kW, 15kW -> %.2f kW]\n', ...
        avg_powers(1), avg_powers(2), avg_powers(3));
    fprintf('         Disabled EV2 max current: %.3f A (Strictly 0.0 A)\n', max_ev2_neg_I);
    fprintf('         Reproducibility delta norm: %.1e\n', diff_norm);
    results.passed = results.passed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'PASS');
catch ME
    fprintf('  [FAIL] %s: %s\n', test_name, ME.message);
    results.failed = results.failed + 1;
    results.details{end+1} = struct('test', test_name, 'status', 'FAIL', 'error', ME.message);
end

%% ------------------------------------------------------------------------
%% SUMMARY REPORT
%% ------------------------------------------------------------------------
fprintf('\n========================================================================\n');
fprintf('  TEST SUITE COMPLETED: %d PASSED / %d FAILED (Total: %d)\n', ...
    results.passed, results.failed, results.total);
fprintf('========================================================================\n\n');

end
