function pass = test_bay_and_vehicle_flow()
% TEST_BAY_AND_VEHICLE_FLOW Verification test for bay allocation,
% vehicle navigation, parking tolerances, and connector handshake.

fprintf('=== RUNNING TEST SUITE: BAY ALLOCATION & VEHICLE FLOW ===\n');
cfg = station_config();
pass = true;

%% Test 1: Charging Bay Manager Initialization & Allocation
bays = charging_bay_manager.init_bays(cfg);

if length(bays) == 4
    fprintf('[PASS] Test 1.1: Bay Manager initialized with 4 distinct bays\n');
else
    fprintf('[FAIL] Test 1.1: Expected 4 bays, got %d\n', length(bays));
    pass = false;
end

[bay_id_1, bays] = charging_bay_manager.request_bay(bays, 101);
[bay_id_2, bays] = charging_bay_manager.request_bay(bays, 102);

if bay_id_1 == 1 && bay_id_2 == 2 && strcmpi(bays(1).status, "RESERVED")
    fprintf('[PASS] Test 1.2: Sequential bay allocation: EV #101 -> Bay 1, EV #102 -> Bay 2\n');
else
    fprintf('[FAIL] Test 1.2: Bay allocation failure: Bay1=%d, Bay2=%d\n', bay_id_1, bay_id_2);
    pass = false;
end

%% Test 2: Double Allocation Prevention
[bay_id_3, bays] = charging_bay_manager.request_bay(bays, 103);
[bay_id_4, bays] = charging_bay_manager.request_bay(bays, 104);
[bay_id_5, bays] = charging_bay_manager.request_bay(bays, 105); % 5th vehicle when 4 bays are taken

if bay_id_5 == 0
    fprintf('[PASS] Test 2.1: Bay capacity overflow protection: 5th EV request rejected (bay_id=0)\n');
else
    fprintf('[FAIL] Test 2.1: Overflow bay allocated improperly: %d\n', bay_id_5);
    pass = false;
end

%% Test 3: Geometric Parking Verification
bay_1_center = cfg.bays(1).center;
bay_1_heading = cfg.bays(1).orientation;

% Accurate parking position
veh_pos_good = bay_1_center + [0.05, -0.05, 0.0];
veh_heading_good = bay_1_heading + 0.05;

is_good_parked = charging_bay_manager.verify_parking(...
    veh_pos_good, veh_heading_good, bay_1_center, bay_1_heading, 0.20, 0.15);

% Misaligned parking position
veh_pos_bad = bay_1_center + [0.8, 1.2, 0.0];
is_bad_parked = charging_bay_manager.verify_parking(...
    veh_pos_bad, veh_heading_good, bay_1_center, bay_1_heading, 0.20, 0.15);

if is_good_parked && ~is_bad_parked
    fprintf('[PASS] Test 3.1: Geometric parking verification: Passed for aligned EV, rejected for misaligned EV\n');
else
    fprintf('[FAIL] Test 3.1: Parking verification error: Good=%d, Bad=%d\n', is_good_parked, is_bad_parked);
    pass = false;
end

%% Test 4: Connector 3-Tier State Handshake
conn = connector_manager.init_connector(1, 1);
charger_pos = cfg.bays(1).charger_pos;
veh_inlet   = cfg.fleet_templates(2).inlet_offset;

% Update with CONNECT command over 3 seconds (speed=0.5/s -> full lock in 2s)
for step = 1:6
    [conn, cable_pts, plug_p] = connector_manager.update_connector(...
        conn, charger_pos, bay_1_center, bay_1_heading, veh_inlet, 0.5, "CONNECT");
end

if strcmpi(conn.state, "LOCKED") && conn.electrical_connected
    fprintf('[PASS] Test 4.1: Connector Extension & Electrical Lock: State=%s, Interlock Closed\n', conn.state);
else
    fprintf('[FAIL] Test 4.1: Connector failed to lock: State=%s, Interlock=%d\n', conn.state, conn.electrical_connected);
    pass = false;
end

if size(cable_pts, 1) == 15 && size(cable_pts, 2) == 3
    fprintf('[PASS] Test 4.2: 3D Cable Spline Generated: 15 spatial coordinate points with catenary sag\n');
else
    fprintf('[FAIL] Test 4.2: Cable points dimension mismatch\n');
    pass = false;
end

%% Test 5: Bay Release Upon Departure
bays = charging_bay_manager.release_bay(bays, 1);
if strcmpi(bays(1).status, "AVAILABLE") && bays(1).assigned_vehicle_id == 0
    fprintf('[PASS] Test 5.1: Bay Release: Bay 1 successfully restored to AVAILABLE state\n');
else
    fprintf('[FAIL] Test 5.1: Bay release failed: %s\n', bays(1).status);
    pass = false;
end

%% Final Summary
if pass
    fprintf('\n>>> ALL BAY ALLOCATION & VEHICLE FLOW TESTS PASSED! <<<\n\n');
else
    fprintf('\n>>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<\n\n');
end

end
