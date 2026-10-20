function pass = test_multi_vehicle()
% TEST_MULTI_VEHICLE Integration test for multi-EV concurrency, independent
% state isolation, queue management, bay saturation, and fault propagation.

fprintf('=== RUNNING TEST SUITE: MULTI-VEHICLE OPERATION & STATE ISOLATION ===\n');
cfg = station_config();
pass = true;

%% Test 1: Independent Battery State Isolation
% Verify that modifying Car A's state does NOT affect Car B or Car C
vA = vehicle_manager.create_vehicle(1, 1, 0.20, 0.90, 0.98, 25.0, cfg); % Compact EV (40 Ah)
vB = vehicle_manager.create_vehicle(2, 2, 0.50, 0.90, 0.95, 25.0, cfg); % Sedan (50 Ah)
vC = vehicle_manager.create_vehicle(3, 4, 0.80, 0.90, 0.88, 28.0, cfg); % Executive (75 Ah)

% Mutate Car A
vA.battery.SOC = 0.99;
vA.battery.Temperature = 48.0;

if vB.battery.SOC == 0.50 && vC.battery.SOC == 0.80 && vB.battery.Temperature == 25.0
    fprintf('[PASS] Test 1: State Isolation verified: Modifying Car A did not contaminate Car B or Car C\n');
else
    fprintf('[FAIL] Test 1: State cross-contamination detected!\n');
    pass = false;
end

%% Test 2: Full Bay Saturation & Queue Handling
bays = charging_bay_manager.init_bays(cfg);
v_fleet = [];
for i = 1:5
    v_fleet = [v_fleet, vehicle_manager.create_vehicle(i, 2, 0.30, 0.90, 0.95, 25.0, cfg)];
end

allocated_bays = zeros(5, 1);
for i = 1:5
    [allocated_bays(i), bays] = charging_bay_manager.request_bay(bays, v_fleet(i).id);
end

if all(allocated_bays(1:4) == (1:4)') && allocated_bays(5) == 0
    fprintf('[PASS] Test 2: Bay saturation handled properly: 4 bays occupied, 5th EV placed in queue\n');
else
    fprintf('[FAIL] Test 2: Improper bay saturation allocation\n');
    pass = false;
end

%% Test 3: Multi-Vehicle Concurrent Charging Under Grid Limit
% Set up chargers & connectors
chargers = repmat(struct(), 4, 1);
connectors = repmat(struct(), 4, 1);
for i = 1:4
    chargers(i).id = i;
    chargers(i).bay_id = i;
    chargers(i).fault_active = false;
    chargers(i).status = "CHARGING";
    chargers(i).energy_delivered_kWh = 0.0;
    
    connectors(i) = connector_manager.init_connector(i, i);
    connectors(i).state = "LOCKED";
    connectors(i).electrical_connected = true;
    
    v_fleet(i).state = "CHARGING";
    v_fleet(i).assigned_bay = i;
end

[alloc_kW, T_pred_all, diag] = station_power_allocator.allocate_power(...
    v_fleet(1:4), chargers, connectors, 'predictive_opt', cfg);

if diag.total_allocated_kW <= cfg.station.grid_power_limit + 1e-4 && all(alloc_kW > 0)
    fprintf('[PASS] Test 3: Concurrent 4-EV Charging: Total allocated = %.2f kW <= Grid limit (%.1f kW)\n', ...
        diag.total_allocated_kW, cfg.station.grid_power_limit);
else
    fprintf('[FAIL] Test 3: Concurrent power allocation failure\n');
    pass = false;
end

%% Test 4: Fault Propagation in Concurrent Fleet
% Inject fault on EV #2: Over-temperature
v_fleet(2).battery.Temperature = 46.5; % Exceeds 45 C trip

[alloc_after_fault, ~, diag_fault] = station_power_allocator.allocate_power(...
    v_fleet(1:4), chargers, connectors, 'predictive_opt', cfg);

if alloc_after_fault(2) == 0.0 && alloc_after_fault(1) > 0
    fprintf('[PASS] Test 4: Fault isolation: Over-temp EV #2 instantly de-allocated (0 kW); others continue\n');
else
    fprintf('[FAIL] Test 4: Faulted EV was still allocated power: %.2f kW\n', alloc_after_fault(2));
    pass = false;
end

%% Final Summary
if pass
    fprintf('\n>>> ALL MULTI-VEHICLE INTEGRATION TESTS PASSED! <<<\n\n');
else
    fprintf('\n>>> SOME TESTS FAILED! <<<\n\n');
end

end
