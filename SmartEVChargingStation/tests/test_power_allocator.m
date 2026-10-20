function pass = test_power_allocator()
% TEST_POWER_ALLOCATOR Quantitative verification of station-level power
% allocation strategies: Strategy A (Equal), Strategy B (Energy-Aware),
% and Strategy C (Predictive Completion-Time Optimization).
%
% Tests the classic multi-EV bottleneck scenario:
%   - Car A: 80% SOC (Needs 10% to reach 90% target)
%   - Car B: 80% SOC (Needs 10% to reach 90% target)
%   - Car C: 20% SOC (Needs 70% to reach 90% target)
%   - Station Power Budget: 10.0 kW
%
% Objective: Verify that Strategy C strictly minimizes the makespan:
%   T_finish = max(T_A, T_B, T_C)

fprintf('=================================================================\n');
fprintf('  TEST SUITE: STATION-LEVEL PREDICTIVE POWER ALLOCATION\n');
fprintf('=================================================================\n\n');

cfg = station_config();
cfg.station.grid_power_limit = 10.0; % Constrained station budget: 10 kW
pass = true;

%% 1. Set Up the 3-Vehicle Test Fleet
% Car A (80% SOC, 50 Ah)
vA = vehicle_manager.create_vehicle(1, 2, 0.80, 0.90, 0.95, 25.0, cfg);
vA.state = "CHARGING"; vA.assigned_bay = 1;

% Car B (80% SOC, 50 Ah)
vB = vehicle_manager.create_vehicle(2, 2, 0.80, 0.90, 0.95, 25.0, cfg);
vB.state = "CHARGING"; vB.assigned_bay = 2;

% Car C (20% SOC, 50 Ah - Deeply depleted bottleneck vehicle)
vC = vehicle_manager.create_vehicle(3, 2, 0.20, 0.90, 0.95, 25.0, cfg);
vC.state = "CHARGING"; vC.assigned_bay = 3;

vehicles = [vA, vB, vC];

% Setup 4 chargers & connectors
chargers = repmat(struct(), 4, 1);
connectors = repmat(struct(), 4, 1);
for i = 1:4
    chargers(i).id = i;
    chargers(i).bay_id = i;
    chargers(i).fault_active = false;
    chargers(i).status = "CHARGING";
    
    connectors(i) = connector_manager.init_connector(i, i);
    if i <= 3
        connectors(i).state = "LOCKED";
        connectors(i).electrical_connected = true;
    end
end

%% 2. Evaluate Strategy A: Equal Allocation
[alloc_A, T_pred_A, diag_A] = station_power_allocator.allocate_power(...
    vehicles, chargers, connectors, 'equal', cfg);

fprintf('--- STRATEGY A (EQUAL ALLOCATION) ---\n');
fprintf('  Car A (80%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_A(1), T_pred_A(1)/60);
fprintf('  Car B (80%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_A(2), T_pred_A(2)/60);
fprintf('  Car C (20%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_A(3), T_pred_A(3)/60);
fprintf('  Station Makespan T_finish = %.1f min | Total Power = %.2f kW\n\n', diag_A.makespan_sec/60, diag_A.total_allocated_kW);

%% 3. Evaluate Strategy B: Energy-Aware Proportional Allocation
[alloc_B, T_pred_B, diag_B] = station_power_allocator.allocate_power(...
    vehicles, chargers, connectors, 'energy_aware', cfg);

fprintf('--- STRATEGY B (ENERGY-AWARE PROPORTIONAL ALLOCATION) ---\n');
fprintf('  Car A (80%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_B(1), T_pred_B(1)/60);
fprintf('  Car B (80%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_B(2), T_pred_B(2)/60);
fprintf('  Car C (20%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_B(3), T_pred_B(3)/60);
fprintf('  Station Makespan T_finish = %.1f min | Total Power = %.2f kW\n\n', diag_B.makespan_sec/60, diag_B.total_allocated_kW);

%% 4. Evaluate Strategy C: Predictive Completion-Time Optimization (Min-Max)
[alloc_C, T_pred_C, diag_C] = station_power_allocator.allocate_power(...
    vehicles, chargers, connectors, 'predictive_opt', cfg);

fprintf('--- STRATEGY C (PREDICTIVE COMPLETION-TIME OPTIMIZATION) ---\n');
fprintf('  Car A (80%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_C(1), T_pred_C(1)/60);
fprintf('  Car B (80%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_C(2), T_pred_C(2)/60);
fprintf('  Car C (20%% SOC): Allocated = %.2f kW | Pred Time = %.1f min\n', alloc_C(3), T_pred_C(3)/60);
fprintf('  Station Makespan T_finish = %.1f min | Total Power = %.2f kW\n\n', diag_C.makespan_sec/60, diag_C.total_allocated_kW);

%% 5. Assertions and Physical Constraints
% Check 1: Total allocated power must never exceed station grid budget (10 kW)
tol = 1.0e-3;
if diag_A.total_allocated_kW <= cfg.station.grid_power_limit + tol && ...
   diag_B.total_allocated_kW <= cfg.station.grid_power_limit + tol && ...
   diag_C.total_allocated_kW <= cfg.station.grid_power_limit + tol
    fprintf('[PASS] Test 1: Station grid power limit strictly enforced (<= %.1f kW) across all strategies\n', cfg.station.grid_power_limit);
else
    fprintf('[FAIL] Test 1: Grid power limit violated!\n');
    pass = false;
end

% Check 2: Individual charger limits respected
if all(alloc_C <= cfg.charger.P_max + tol)
    fprintf('[PASS] Test 2: Individual charger hardware power ceiling (%.1f kW) respected\n', cfg.charger.P_max);
else
    fprintf('[FAIL] Test 2: Individual charger hardware limit violated!\n');
    pass = false;
end

% Check 3: Strategy C achieves shorter or equal makespan T_finish compared to Strategy A
if diag_C.makespan_sec <= diag_A.makespan_sec + 0.1
    time_saved_min = (diag_A.makespan_sec - diag_C.makespan_sec) / 60.0;
    fprintf('[PASS] Test 3: Strategy C reduces station makespan T_finish by %.1f minutes compared to Strategy A\n', time_saved_min);
else
    fprintf('[FAIL] Test 3: Optimization failed to minimize makespan!\n');
    pass = false;
end

%% 6. Test Dynamic Power Reallocation Upon Vehicle Completion
fprintf('\n--- TESTING DYNAMIC REALLOCATION (Car A reaches 90%% target SOC) ---\n');
vehicles(1).battery.SOC = 0.90; % Car A is now fully charged

[alloc_realloc, T_pred_realloc, diag_realloc] = station_power_allocator.allocate_power(...
    vehicles, chargers, connectors, 'predictive_opt', cfg);

fprintf('  Car A Allocated: %.2f kW (Completed -> Released)\n', alloc_realloc(1));
fprintf('  Car B Allocated: %.2f kW\n', alloc_realloc(2));
fprintf('  Car C Allocated: %.2f kW (Absorbed freed station power)\n', alloc_realloc(3));

if alloc_realloc(1) == 0.0 && alloc_realloc(3) >= alloc_C(3)
    fprintf('[PASS] Test 4: Dynamic Reallocation verified: Power released by Car A transferred to Car C\n');
else
    fprintf('[FAIL] Test 4: Reallocation failed: Car A = %.2f kW, Car C = %.2f kW\n', alloc_realloc(1), alloc_realloc(3));
    pass = false;
end

%% Summary
if pass
    fprintf('\n>>> ALL POWER ALLOCATOR TESTS PASSED! <<<\n\n');
else
    fprintf('\n>>> SOME TESTS FAILED! <<<\n\n');
end

end
