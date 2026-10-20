function cfg = station_config()
% STATION_CONFIG Authoritative configuration parameters for the 3D Smart
% EV Charging Station simulation.
%
% Defines geometric, electrical, electrochemical, control, and visualization
% settings in a single centralized, validated structure.

%% ========================================================================
% 1. SIMULATION TIMING AND EXECUTION
% ========================================================================
cfg.sim.dt = 0.5;                     % Base simulation time step [s]
cfg.sim.time_acceleration = 10;       % Real-time acceleration factor for UI/demo
cfg.sim.max_time = 7200;              % Maximum simulation duration [s]
cfg.sim.enable_predictive = true;     % Enable AI BSI & Thermal forecasting

%% ========================================================================
% 2. 3D STATION GEOMETRY AND LAYOUT (Coordinates in Meters: [X, Y, Z])
% ========================================================================
% Station boundary: 40m (X) x 30m (Y)
cfg.geo.station_length = 40.0;
cfg.geo.station_width  = 30.0;

% Entrance & Exit road waypoints
cfg.geo.entrance_spawn = [ 2.0,  3.0, 0.0];   % Spawning point for incoming EVs
cfg.geo.entrance_lane  = [12.0,  3.0, 0.0];   % Driving lane entry
cfg.geo.main_lane_turn = [32.0,  3.0, 0.0];   % Turn to circulation lane
cfg.geo.circ_lane_top  = [32.0, 24.0, 0.0];   % Driving lane along bays
cfg.geo.exit_lane      = [ 8.0, 24.0, 0.0];   % Path to exit
cfg.geo.exit_gate      = [ 2.0, 24.0, 0.0];   % Station departure exit gate

% 4 Dedicated Fast Charging Bays (Facing south into main bay lane)
% Bay dimensions: 5.5m long x 2.8m wide
cfg.geo.bay_width  = 3.2;
cfg.geo.bay_length = 5.5;

cfg.bays(1).id = 1;
cfg.bays(1).center = [12.0, 16.0, 0.0];
cfg.bays(1).approach = [12.0, 24.0, 0.0];
cfg.bays(1).charger_pos = [12.0, 12.8, 0.0];
cfg.bays(1).orientation = -pi/2;  % Facing North/parking orientation

cfg.bays(2).id = 2;
cfg.bays(2).center = [18.0, 16.0, 0.0];
cfg.bays(2).approach = [18.0, 24.0, 0.0];
cfg.bays(2).charger_pos = [18.0, 12.8, 0.0];
cfg.bays(2).orientation = -pi/2;

cfg.bays(3).id = 3;
cfg.bays(3).center = [24.0, 16.0, 0.0];
cfg.bays(3).approach = [24.0, 24.0, 0.0];
cfg.bays(3).charger_pos = [24.0, 12.8, 0.0];
cfg.bays(3).orientation = -pi/2;

cfg.bays(4).id = 4;
cfg.bays(4).center = [30.0, 16.0, 0.0];
cfg.bays(4).approach = [30.0, 24.0, 0.0];
cfg.bays(4).charger_pos = [30.0, 12.8, 0.0];
cfg.bays(4).orientation = -pi/2;

%% ========================================================================
% 3. CHARGER HARDWARE RATINGS (Individual DC Fast Charger Kiosks)
% ========================================================================
cfg.charger.num_chargers = 4;
cfg.charger.V_min = 36.0;            % Minimum DC output voltage [V]
cfg.charger.V_max = 58.0;            % Maximum DC output voltage [V]
cfg.charger.I_max = 85.0;            % Maximum continuous current [A]
cfg.charger.P_max = 4.5;             % Maximum output power per charger [kW]
cfg.charger.efficiency = 0.94;       % Power conversion efficiency (94%)
cfg.charger.slew_rate = 10.0;        % Max current slew rate [A/s]
cfg.charger.cable_length = 3.5;      % Physical cable reach [m]

% Station Grid Connection Limit & Optimization Strategy
cfg.station.grid_power_limit = 14.0; % Total station power constraint [kW]
cfg.station.strategy = 'predictive_opt'; % 'predictive_opt' (Min-Max Makespan), 'energy_aware', 'equal'
cfg.station.enable_power_sharing = true; % Dynamic station-level power allocator

%% ========================================================================
% 4. BATTERY CELL & PACK PARAMETERS (Aligned with V2.1 Project Architecture)
% ========================================================================
cfg.battery.V_nom = 48.0;            % Nominal pack voltage [V]
cfg.battery.V_min = 40.0;            % Hardware lower cutoff [V]
cfg.battery.V_max = 54.6;            % Max charging cutoff voltage [V]
cfg.battery.T_ambient = 25.0;        % Ambient temperature [deg C]
cfg.battery.T_warning = 40.0;        % BMS thermal warning limit [deg C]
cfg.battery.T_trip    = 45.0;        % BMS over-temperature emergency cutoff [deg C]

% Thermal Dynamics (Convective + Resistive Heating)
cfg.battery.Cth = 40000.0;           % Thermal capacitance [J/deg C]
cfg.battery.h_thermal = 20.0;        % Convective heat dissipation [W/deg C]

% Degradation coefficient per second of charging
cfg.battery.degradation_coeff = 2.0e-8;

% Empirical OCV-SOC Lookup Table (from Phase1_10_Adaptive_BMS_V2.m)
cfg.battery.SOC_table = [0.0, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00];
cfg.battery.OCV_table = [40.0, 41.2, 42.8, 44.2, 45.3, 46.2, 47.1, 48.0, 50.2, 52.8, 54.6];

%% ========================================================================
% 5. BATTERY STRESS INDEX (BSI) CONFIGURATION
% ========================================================================
cfg.bsi.wC   = 0.35;                 % Weight for C-rate stress
cfg.bsi.wT   = 0.25;                 % Weight for Thermal stress
cfg.bsi.wSOC = 0.20;                 % Weight for high SOC stress
cfg.bsi.wR   = 0.10;                 % Weight for internal resistance degradation
cfg.bsi.wSOH = 0.10;                 % Weight for SOH loss

cfg.bsi.warning_threshold = 45.0;    % BSI warning - derate current
cfg.bsi.high_threshold    = 60.0;    % BSI high stress - aggressive derate
cfg.bsi.trip_threshold    = 80.0;    % BSI critical safety trip threshold

%% ========================================================================
% 6. VEHICLE FLEET TEMPLATES (Diverse realistic vehicle archetypes)
% ========================================================================
% Vehicle Type 1: Compact City EV
cfg.fleet_templates(1).type_name = 'Compact City EV';
cfg.fleet_templates(1).Q_nom = 40.0;          % Capacity [Ah]
cfg.fleet_templates(1).R_initial = 0.055;     % New cell resistance [Ohm]
cfg.fleet_templates(1).C_max = 1.5;           % Max C-rate allowed
cfg.fleet_templates(1).color = [0.18, 0.55, 0.92]; % Blue
cfg.fleet_templates(1).body_size = [3.8, 1.7, 1.4]; % [L, W, H] meters
cfg.fleet_templates(1).inlet_offset = [-1.4, 0.85, 0.7]; % Left rear quarter

% Vehicle Type 2: Standard Sedan EV (Baseline project benchmark)
cfg.fleet_templates(2).type_name = 'Standard Sedan EV';
cfg.fleet_templates(2).Q_nom = 50.0;          % Capacity [Ah] (Standard project battery)
cfg.fleet_templates(2).R_initial = 0.050;     % [Ohm]
cfg.fleet_templates(2).C_max = 1.5;           % [C]
cfg.fleet_templates(2).color = [0.22, 0.78, 0.45]; % Emerald Green
cfg.fleet_templates(2).body_size = [4.4, 1.85, 1.45];
cfg.fleet_templates(2).inlet_offset = [-1.6, 0.92, 0.72];

% Vehicle Type 3: Fleet Delivery Van
cfg.fleet_templates(3).type_name = 'Fleet Cargo Van';
cfg.fleet_templates(3).Q_nom = 65.0;          % Capacity [Ah]
cfg.fleet_templates(3).R_initial = 0.042;     % [Ohm]
cfg.fleet_templates(3).C_max = 1.3;           % [C]
cfg.fleet_templates(3).color = [0.95, 0.65, 0.15]; % Amber Yellow
cfg.fleet_templates(3).body_size = [4.8, 1.95, 1.9];
cfg.fleet_templates(3).inlet_offset = [-1.8, 0.98, 0.8];

% Vehicle Type 4: Premium EV (Aged/High-Stress test archetype)
cfg.fleet_templates(4).type_name = 'Executive Long-Range EV';
cfg.fleet_templates(4).Q_nom = 75.0;          % Capacity [Ah]
cfg.fleet_templates(4).R_initial = 0.038;     % [Ohm]
cfg.fleet_templates(4).C_max = 1.5;           % [C]
cfg.fleet_templates(4).color = [0.85, 0.25, 0.25]; % Crimson Red
cfg.fleet_templates(4).body_size = [4.7, 1.9, 1.42];
cfg.fleet_templates(4).inlet_offset = [-1.7, 0.95, 0.72];

%% ========================================================================
% 7. MOTION AND KINEMATICS
% ========================================================================
cfg.motion.cruise_speed = 3.5;       % Driving lane speed [m/s] (~12 km/h)
cfg.motion.parking_speed = 1.0;      % Maneuvering speed [m/s]
cfg.motion.max_accel    = 1.5;       % Maximum acceleration [m/s^2]
cfg.motion.arrival_tolerance = 0.25; % Waypoint capture radius [m]
cfg.motion.parking_tolerance = 0.15; % Precise parking alignment [m]

%% ========================================================================
% 8. DEFAULT USER-CONFIGURABLE VEHICLES (Dashboard Editable Battery Profiles)
% ========================================================================
cfg.default_user_vehicles = repmat(struct(), 4, 1);

cfg.default_user_vehicles(1).id = 1;
cfg.default_user_vehicles(1).type_name = 'Standard Sedan EV';
cfg.default_user_vehicles(1).template_idx = 2;
cfg.default_user_vehicles(1).Q_nom = 50.0;
cfg.default_user_vehicles(1).initial_SOC = 0.25;
cfg.default_user_vehicles(1).target_SOC = 0.90;
cfg.default_user_vehicles(1).initial_SOH = 0.96;
cfg.default_user_vehicles(1).initial_Temp = 25.0;
cfg.default_user_vehicles(1).T_ambient = 25.0;
cfg.default_user_vehicles(1).R_initial = 0.050;
cfg.default_user_vehicles(1).C_max = 1.5;
cfg.default_user_vehicles(1).V_min = 40.0;
cfg.default_user_vehicles(1).V_max = 54.6;
cfg.default_user_vehicles(1).I_max = 85.0;
cfg.default_user_vehicles(1).is_enabled = true;

cfg.default_user_vehicles(2).id = 2;
cfg.default_user_vehicles(2).type_name = 'Compact City EV';
cfg.default_user_vehicles(2).template_idx = 1;
cfg.default_user_vehicles(2).Q_nom = 40.0;
cfg.default_user_vehicles(2).initial_SOC = 0.35;
cfg.default_user_vehicles(2).target_SOC = 0.85;
cfg.default_user_vehicles(2).initial_SOH = 0.98;
cfg.default_user_vehicles(2).initial_Temp = 25.0;
cfg.default_user_vehicles(2).T_ambient = 25.0;
cfg.default_user_vehicles(2).R_initial = 0.055;
cfg.default_user_vehicles(2).C_max = 1.5;
cfg.default_user_vehicles(2).V_min = 40.0;
cfg.default_user_vehicles(2).V_max = 54.6;
cfg.default_user_vehicles(2).I_max = 85.0;
cfg.default_user_vehicles(2).is_enabled = true;

cfg.default_user_vehicles(3).id = 3;
cfg.default_user_vehicles(3).type_name = 'Fleet Delivery Van';
cfg.default_user_vehicles(3).template_idx = 3;
cfg.default_user_vehicles(3).Q_nom = 65.0;
cfg.default_user_vehicles(3).initial_SOC = 0.20;
cfg.default_user_vehicles(3).target_SOC = 0.85;
cfg.default_user_vehicles(3).initial_SOH = 0.92;
cfg.default_user_vehicles(3).initial_Temp = 26.5;
cfg.default_user_vehicles(3).T_ambient = 25.0;
cfg.default_user_vehicles(3).R_initial = 0.042;
cfg.default_user_vehicles(3).C_max = 1.3;
cfg.default_user_vehicles(3).V_min = 40.0;
cfg.default_user_vehicles(3).V_max = 54.6;
cfg.default_user_vehicles(3).I_max = 85.0;
cfg.default_user_vehicles(3).is_enabled = true;

cfg.default_user_vehicles(4).id = 4;
cfg.default_user_vehicles(4).type_name = 'Executive Long-Range EV';
cfg.default_user_vehicles(4).template_idx = 4;
cfg.default_user_vehicles(4).Q_nom = 75.0;
cfg.default_user_vehicles(4).initial_SOC = 0.40;
cfg.default_user_vehicles(4).target_SOC = 0.90;
cfg.default_user_vehicles(4).initial_SOH = 0.85;
cfg.default_user_vehicles(4).initial_Temp = 27.0;
cfg.default_user_vehicles(4).T_ambient = 25.0;
cfg.default_user_vehicles(4).R_initial = 0.038;
cfg.default_user_vehicles(4).C_max = 1.5;
cfg.default_user_vehicles(4).V_min = 40.0;
cfg.default_user_vehicles(4).V_max = 54.6;
cfg.default_user_vehicles(4).I_max = 85.0;
cfg.default_user_vehicles(4).is_enabled = true;

end
