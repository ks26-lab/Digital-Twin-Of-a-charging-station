function sim_results = main_station_simulation(varargin)
% MAIN_STATION_SIMULATION Master coordinator and entry point for the 3D Smart
% EV Charging Station Digital Twin with User-Configured Software Simulation.
%
% Integrates:
%   1. Direct Dashboard User Inputs (Per-Vehicle Capacity, SOC, SOH, Temp, Rint, Limits)
%   2. Rigid Physical Input Validation (No invalid configurations reach the engine)
%   3. Closed-Loop Battery Multiphysics (OCV, Rint(SOC,SOH,T), Lumped Thermal Balance)
%   4. Predictive Analytics Forecasting & Proactive BMS C-Rate Advisory
%   5. Stress-Aware Multi-Stage Adaptive C-rate Controller with CC-CV Clamping
%   6. Non-Linear CC-CV Charging-Time Predictor
%   7. Station-Level Predictive Power Allocator (Min-Max Makespan Optimization)
%   8. Converter Efficiency, Interlock Safety Gate, and Cable Dynamics
%   9. Authoritative Live Telemetry Dashboard and Procedural 3D Visualizer
%
% Usage:
%   sim_results = main_station_simulation();
%   sim_results = main_station_simulation('headless', true, 'duration', 600);
%   sim_results = main_station_simulation('initial_placement', 'bay');

%% 1. Parse Input Options
p = inputParser;
addParameter(p, 'duration', 1200, @isnumeric);
addParameter(p, 'strategy', 'adaptive', @(x) any(validatestring(x, {'adaptive', 'fixed'})));
addParameter(p, 'power_strategy', 'predictive_opt', @(x) any(validatestring(x, {'predictive_opt', 'energy_aware', 'equal'})));
addParameter(p, 'headless', false, @islogical);
addParameter(p, 'auto_spawn', true, @islogical);
addParameter(p, 'initial_placement', 'entrance', @(x) any(validatestring(x, {'entrance', 'bay'})));
addParameter(p, 'user_config', [], @(x) isempty(x) || isstruct(x));
parse(p, varargin{:});

duration_sec      = p.Results.duration;
bms_strategy      = p.Results.strategy;
power_strategy    = p.Results.power_strategy;
is_headless       = p.Results.headless;
auto_spawn        = p.Results.auto_spawn;
initial_placement = p.Results.initial_placement;
custom_user_cfg   = p.Results.user_config;

fprintf('=================================================================\n');
fprintf('  3D SMART EV CHARGING STATION - DIGITAL TWIN SIMULATION\n');
fprintf('=================================================================\n');
fprintf('  Mode           : Software-Only Digital Twin Simulation\n');
fprintf('  Duration       : %d seconds\n', duration_sec);
fprintf('  BMS Strategy   : %s C-rate control\n', upper(bms_strategy));
fprintf('  Power Strategy : %s\n', upper(power_strategy));
fprintf('  Placement      : %s\n', upper(initial_placement));
fprintf('=================================================================\n\n');

%% 2. Load Central Configuration
cfg = station_config();
dt  = cfg.sim.dt;

%% 3. Load Predictive Analytics Model (Clean, Workspace-Independent)
pred_model = predictive_analytics.get_model();
fprintf('[PREDICTIVE AI] Model Status: %s\n', pred_model.provenance);

%% 4. Initialize Hardware Charging Bays & Kiosks
bays = charging_bay_manager.init_bays(cfg);
chargers = repmat(struct(), cfg.charger.num_chargers, 1);
connectors = repmat(struct(), cfg.charger.num_chargers, 1);

for i = 1:cfg.charger.num_chargers
    chargers(i).id = i;
    chargers(i).bay_id = i;
    chargers(i).status = "AVAILABLE";
    chargers(i).I_out = 0.0;
    chargers(i).V_out = 0.0;
    chargers(i).P_out_kW = 0.0;
    chargers(i).P_grid_kW = 0.0;
    chargers(i).energy_delivered_kWh = 0.0;
    chargers(i).fault_active = false;
    chargers(i).fault_msg = "Normal";
    
    connectors(i) = connector_manager.init_connector(i, i);
end

%% 5. Initialize Interactive Telemetry Dashboard & 3D Visualization
if ~is_headless
    dash  = station_dashboard(cfg, [], false);
    vis3d = visualization_3d(cfg);
    
    % If caller provided a custom user_config, populate dashboard
    if ~isempty(custom_user_cfg)
        if isfield(custom_user_cfg, 'station')
            dash.user_station_cfg = custom_user_cfg.station;
        end
        if isfield(custom_user_cfg, 'vehicles')
            dash.user_vehicle_cfg = custom_user_cfg.vehicles;
        end
    end
    
    active_user_cfg = dash.get_user_config();
else
    dash  = [];
    vis3d = [];
    if isempty(custom_user_cfg)
        active_user_cfg.station.grid_power_limit = cfg.station.grid_power_limit;
        active_user_cfg.station.num_vehicles     = 4;
        active_user_cfg.station.power_strategy   = power_strategy;
        active_user_cfg.station.bms_strategy     = bms_strategy;
        active_user_cfg.station.duration         = duration_sec;
        active_user_cfg.station.dt               = dt;
        active_user_cfg.vehicles                 = cfg.default_user_vehicles;
    else
        active_user_cfg = custom_user_cfg;
    end
end

% Validate Configuration
[is_valid, val_err] = station_dashboard.validate_config(active_user_cfg.station, active_user_cfg.vehicles);
if ~is_valid
    error('Configuration Validation Failed: %s', val_err);
end

% Set Simulation Control Flags
sim_ctrl.is_paused      = false;
sim_ctrl.should_reset   = false;
sim_ctrl.apply_pending  = false;
sim_ctrl.pending_cfg    = [];
sim_ctrl.bms_strategy   = active_user_cfg.station.bms_strategy;
sim_ctrl.power_strategy = active_user_cfg.station.power_strategy;
sim_ctrl.selected_cam   = 1;
sim_ctrl.inject_fault   = false;

if ~is_headless
    dash.set_action_callback(@dashboard_action_handler);
    setup_3d_gui_controls(vis3d.fig_handle, @gui_3d_callback);
end

%% 6. Initialize Vehicle Fleet from Validated Dashboard Inputs
num_active_veh = min(active_user_cfg.station.num_vehicles, length(active_user_cfg.vehicles));
vehicles = [];

for v = 1:num_active_veh
    v_in = active_user_cfg.vehicles(v);
    new_veh = vehicle_manager.create_vehicle(v_in, cfg);
    
    if strcmpi(initial_placement, 'bay') && v <= cfg.charger.num_chargers
        % Place vehicle directly parked in its respective bay
        bay_id = v;
        new_veh.assigned_bay = bay_id;
        new_veh.position     = bays(bay_id).center;
        new_veh.heading      = bays(bay_id).orientation;
        new_veh.speed        = 0.0;
        new_veh.state        = "CHARGING";
        
        bays(bay_id).status      = "OCCUPIED";
        bays(bay_id).occupied_by = new_veh.id;
        
        connectors(bay_id).state = "LOCKED";
        connectors(bay_id).electrical_connected = true;
        connectors(bay_id).tip_pos = new_veh.position + new_veh.inlet_offset;
        
        chargers(bay_id).status = "CONNECTED";
    end
    
    vehicles = [vehicles, new_veh];
end

%% 7. Simulation Timing and Logging Variables
sim_time = 0.0;
dt = active_user_cfg.station.dt;
cfg.station.grid_power_limit = active_user_cfg.station.grid_power_limit;

num_log_steps = floor(duration_sec / dt) + 1;
log_idx = 1;
log_data.time = zeros(num_log_steps, 1);
log_data.station_power_kW = zeros(num_log_steps, 1);
log_data.station_energy_kWh = zeros(num_log_steps, 1);

%% 8. Master Discrete-Time Simulation Loop
step_count = 0;
while sim_time <= duration_sec
    
    % Handle Pause State
    if ~is_headless && isvalid(vis3d.fig_handle)
        while sim_ctrl.is_paused && isvalid(vis3d.fig_handle)
            pause(0.08);
            drawnow;
            if sim_ctrl.should_reset; break; end
        end
        if ~isvalid(vis3d.fig_handle); break; end
    end
    
    % Handle Reset Command
    if sim_ctrl.should_reset
        sim_ctrl.should_reset = false;
        sim_time = 0.0;
        step_count = 0;
        log_idx = 1;
        
        % Reset vehicles to configured initial states
        for v = 1:length(vehicles)
            vehicles(v) = vehicle_manager.reset_vehicle(vehicles(v), cfg);
        end
        for c = 1:length(chargers)
            chargers(c).I_out = 0.0;
            chargers(c).P_out_kW = 0.0;
            chargers(c).P_grid_kW = 0.0;
            chargers(c).energy_delivered_kWh = 0.0;
            chargers(c).status = "AVAILABLE";
            connectors(c) = connector_manager.init_connector(c, c);
        end
        bays = charging_bay_manager.init_bays(cfg);
        fprintf('[SIMULATION] Successfully reset to initial user configuration.\n');
        continue;
    end
    
    % Handle Apply Inputs Command
    if sim_ctrl.apply_pending
        sim_ctrl.apply_pending = false;
        new_cfg = sim_ctrl.pending_cfg;
        if ~isempty(new_cfg)
            cfg.station.grid_power_limit = new_cfg.station.grid_power_limit;
            sim_ctrl.bms_strategy   = new_cfg.station.bms_strategy;
            sim_ctrl.power_strategy = new_cfg.station.power_strategy;
            
            % Update vehicle states
            for v = 1:min(length(vehicles), length(new_cfg.vehicles))
                nv = new_cfg.vehicles(v);
                vehicles(v).battery.target_SOC = nv.target_SOC;
                vehicles(v).battery.C_max      = nv.C_max;
                vehicles(v).battery.I_max      = nv.I_max;
                vehicles(v).battery.V_max      = nv.V_max;
                vehicles(v).is_enabled         = nv.is_enabled;
                vehicles(v).battery.is_enabled = nv.is_enabled;
            end
            fprintf('[SIMULATION] Applied updated user parameters dynamically.\n');
        end
    end
    
    %% STEP 8.1: Update Fleet Kinematics & Lifecycle State Machines
    for v = 1:length(vehicles)
        [vehicles(v), bays] = vehicle_manager.update_vehicle(...
            vehicles(v), bays, dt, sim_ctrl.bms_strategy, cfg);
    end
    
    %% STEP 8.2: Update Physical & Electrical Connectors
    for c = 1:length(connectors)
        bay_id = connectors(c).bay_id;
        v_idx  = find([vehicles.assigned_bay] == bay_id, 1);
        
        if ~isempty(v_idx)
            veh = vehicles(v_idx);
            
            if strcmpi(veh.state, "CONNECTING") || strcmpi(veh.state, "CONNECTED") || strcmpi(veh.state, "CHARGING")
                cmd = "CONNECT";
            elseif strcmpi(veh.state, "DISCONNECTING") || strcmpi(veh.state, "DEPARTING")
                cmd = "DISCONNECT";
            else
                cmd = "HOLD";
            end
            
            chg_pos = bays(bay_id).charger_pos;
            connectors(c) = connector_manager.update_connector(...
                connectors(c), chg_pos, veh.position, veh.heading, veh.inlet_offset, dt, cmd);
            
            if strcmpi(veh.state, "CONNECTING") && connectors(c).electrical_connected
                vehicles(v_idx).state = "CONNECTED";
            elseif strcmpi(veh.state, "DISCONNECTING") && strcmpi(connectors(c).state, "DISCONNECTED")
                vehicles(v_idx).state = "DEPARTING";
                bays = charging_bay_manager.release_bay(bays, bay_id);
                vehicles(v_idx).assigned_bay = 0;
            end
        else
            connectors(c).state = "DISCONNECTED";
            connectors(c).electrical_connected = false;
        end
    end
    
    %% STEP 8.3: Station-Level Power Allocation (Under Station Limit & Makespan Opt)
    [power_allocations, T_pred_all, alloc_diag] = station_power_allocator.allocate_power(...
        vehicles, chargers, connectors, sim_ctrl.power_strategy, cfg);
    
    %% STEP 8.4: Closed-Loop BMS Control & Physical Battery Dynamics
    for c = 1:length(chargers)
        bay_id = chargers(c).bay_id;
        v_idx  = find([vehicles.assigned_bay] == bay_id, 1);
        
        if ~isempty(v_idx)
            veh = vehicles(v_idx);
            is_locked = connectors(c).electrical_connected;
            
            % Update power allocation and predicted completion time
            veh.P_alloc_kW = power_allocations(c);
            veh.T_pred_sec = T_pred_all(c);
            
            % Fault injection
            if sim_ctrl.inject_fault && veh.id == 1
                veh.battery.Temperature = 46.5; % Trigger critical over-temperature
                sim_ctrl.inject_fault = false;
            end
            
            if strcmpi(veh.state, "CHARGING") && is_locked && veh.is_enabled
                % 1. Evaluate Open Circuit Voltage (OCV)
                OCV = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, veh.battery.SOC, 'pchip');
                
                % 2. Run Predictive Analytics for Proactive C-Rate Advisory
                [~, ~, C_max_advice, pred_info] = predictive_analytics.forecast(...
                    pred_model, veh.battery, veh.cycle_count, cfg);
                veh.battery.C_max_advice = C_max_advice;
                veh.pred_info = pred_info;
                
                % 3. BMS Controller (Adaptive or Fixed 1C)
                [bms_cmd, bsi_data, fault] = bms_controller(...
                    veh.battery, OCV, veh.prev_I_cmd, dt, sim_ctrl.bms_strategy, veh.battery.target_SOC, cfg);
                
                % 4. Charger Model (Convert allocated power & BMS limit into feasible current)
                alloc_P_kW = power_allocations(c);
                [chargers(c), I_delivered, P_elec_kW, P_grid_kW] = charger_model(...
                    chargers(c), bms_cmd.I_cmd, veh.battery.Voltage, is_locked, alloc_P_kW, dt, cfg);
                
                % 5. Battery Model Physical State Update (Feedback delivered current)
                [veh.battery, ~] = battery_model(veh.battery, I_delivered, dt, cfg);
                
                % 6. Record Vehicle Telemetry
                veh.prev_I_cmd     = I_delivered;
                veh.I_cmd          = bms_cmd.I_cmd;
                veh.C_rate_cmd     = bms_cmd.C_rate_cmd;
                veh.charging_mode  = bms_cmd.mode;
                veh.BSI            = bsi_data.BSI;
                veh.bsi_data       = bsi_data;
                veh.P_delivered_kW = P_elec_kW;
                
                if fault.active
                    veh.fault_msg = fault.msg;
                end
            else
                % Charger is idle, disconnected, disabled, or complete
                [chargers(c), ~, ~, ~] = charger_model(...
                    chargers(c), 0.0, veh.battery.Voltage, false, 0.0, dt, cfg);
                veh.battery.Current = 0.0;
                veh.battery.Power   = 0.0;
                veh.I_cmd           = 0.0;
                veh.C_rate_cmd      = 0.0;
                veh.charging_mode   = "STOP";
                veh.P_delivered_kW  = 0.0;
            end
            vehicles(v_idx) = veh;
        else
            chargers(c).status = "AVAILABLE";
            chargers(c).I_out = 0.0;
            chargers(c).P_out_kW = 0.0;
            chargers(c).P_grid_kW = 0.0;
        end
    end
    
    %% STEP 8.5: Remove Exited Vehicles (when in entrance/drive mode)
    if ~isempty(vehicles) && ~strcmpi(initial_placement, 'bay')
        exited_mask = strcmpi([vehicles.state], "EXITED");
        vehicles(exited_mask) = [];
    end
    
    %% STEP 8.6: Update Real-Time Dashboard & 3D Visualizer
    if ~is_headless && (mod(step_count, 2) == 0)
        if isvalid(vis3d.fig_handle)
            vis3d.render_vehicles(vehicles);
            vis3d.render_cables(connectors, bays, vehicles);
            vis3d.update_charger_indicators(chargers);
            drawnow limitrate;
        end
        if isvalid(dash.fig_handle)
            dash.update_dashboard(sim_time, vehicles, chargers, bays, alloc_diag);
        end
    end
    
    %% STEP 8.7: Log Station Time-Series
    if log_idx <= num_log_steps
        log_data.time(log_idx) = sim_time;
        log_data.station_power_kW(log_idx) = sum([chargers.P_grid_kW]);
        log_data.station_energy_kWh(log_idx) = sum([chargers.energy_delivered_kWh]);
        log_idx = log_idx + 1;
    end
    
    sim_time = sim_time + dt;
    step_count = step_count + 1;
end

%% 9. Pack Simulation Results
sim_results.time = log_data.time(1:log_idx-1);
sim_results.station_power_kW = log_data.station_power_kW(1:log_idx-1);
sim_results.station_energy_kWh = log_data.station_energy_kWh(1:log_idx-1);
sim_results.total_energy_kWh = sum([chargers.energy_delivered_kWh]);
sim_results.final_vehicles = vehicles;
sim_results.final_chargers = chargers;
sim_results.alloc_diag = alloc_diag;

fprintf('\n>>> SIMULATION COMPLETED SUCCESSFULLY <<<\n');
fprintf('  Final Sim Time       : %.1f seconds\n', sim_time);
fprintf('  Total Energy Injected: %.3f kWh\n', sim_results.total_energy_kWh);

%% ========================================================================
% HELPER CALLBACKS FOR DASHBOARD AND 3D UI
% ========================================================================
    function dashboard_action_handler(action_name, user_cfg)
        switch upper(action_name)
            case 'TOGGLE_PLAY'
                sim_ctrl.is_paused = ~sim_ctrl.is_paused;
                fprintf('[DASHBOARD] Play/Pause toggled: is_paused = %d\n', sim_ctrl.is_paused);
            case 'APPLY_INPUTS'
                sim_ctrl.apply_pending = true;
                sim_ctrl.pending_cfg   = user_cfg;
                fprintf('[DASHBOARD] User inputs scheduled for dynamic application.\n');
            case 'RESET'
                sim_ctrl.should_reset = true;
                fprintf('[DASHBOARD] Reset requested.\n');
            case 'COMPARE_STRATEGIES'
                fprintf('[DASHBOARD] Launching Strategy Comparison on Configured Fleet...\n');
                compare_allocation_strategies(user_cfg.vehicles, user_cfg.station, cfg);
        end
    end

    function setup_3d_gui_controls(fig, cb)
        p = uipanel('Parent', fig, 'Position', [0.01, 0.01, 0.98, 0.07], ...
            'BackgroundColor', [0.14, 0.17, 0.22], 'BorderType', 'line', 'HighlightColor', [0.3, 0.35, 0.45]);
        
        uicontrol('Parent', p, 'Style', 'pushbutton', 'String', 'PLAY / PAUSE', ...
            'Units', 'normalized', 'Position', [0.01, 0.15, 0.15, 0.70], ...
            'FontSize', 9, 'FontWeight', 'bold', 'BackgroundColor', [0.25, 0.5, 0.8], ...
            'ForegroundColor', 'w', 'Callback', @(~,~) cb('TOGGLE_PAUSE'));
        
        uicontrol('Parent', p, 'Style', 'pushbutton', 'String', 'CYCLE POWER OPT', ...
            'Units', 'normalized', 'Position', [0.18, 0.15, 0.18, 0.70], ...
            'FontSize', 9, 'FontWeight', 'bold', 'BackgroundColor', [0.85, 0.5, 0.15], ...
            'ForegroundColor', 'w', 'Callback', @(~,~) cb('CYCLE_POWER_STRAT'));
        
        uicontrol('Parent', p, 'Style', 'pushbutton', 'String', 'INJECT FAULT (V1)', ...
            'Units', 'normalized', 'Position', [0.38, 0.15, 0.18, 0.70], ...
            'FontSize', 9, 'FontWeight', 'bold', 'BackgroundColor', [0.85, 0.25, 0.25], ...
            'ForegroundColor', 'w', 'Callback', @(~,~) cb('INJECT_FAULT'));
        
        uicontrol('Parent', p, 'Style', 'pushbutton', 'String', 'CAM: ISO', ...
            'Units', 'normalized', 'Position', [0.58, 0.15, 0.12, 0.70], ...
            'FontSize', 8, 'BackgroundColor', [0.2, 0.25, 0.32], 'ForegroundColor', 'w', ...
            'Callback', @(~,~) cb('CAM_ISO'));
        
        uicontrol('Parent', p, 'Style', 'pushbutton', 'String', 'CAM: BAYS', ...
            'Units', 'normalized', 'Position', [0.72, 0.15, 0.12, 0.70], ...
            'FontSize', 8, 'BackgroundColor', [0.2, 0.25, 0.32], 'ForegroundColor', 'w', ...
            'Callback', @(~,~) cb('CAM_BAYS'));
        
        uicontrol('Parent', p, 'Style', 'pushbutton', 'String', 'CAM: TOP', ...
            'Units', 'normalized', 'Position', [0.86, 0.15, 0.12, 0.70], ...
            'FontSize', 8, 'BackgroundColor', [0.2, 0.25, 0.32], 'ForegroundColor', 'w', ...
            'Callback', @(~,~) cb('CAM_TOP'));
    end

    function gui_3d_callback(action)
        switch action
            case 'TOGGLE_PAUSE'
                sim_ctrl.is_paused = ~sim_ctrl.is_paused;
            case 'CYCLE_POWER_STRAT'
                if strcmpi(sim_ctrl.power_strategy, 'predictive_opt')
                    sim_ctrl.power_strategy = 'energy_aware';
                elseif strcmpi(sim_ctrl.power_strategy, 'energy_aware')
                    sim_ctrl.power_strategy = 'equal';
                else
                    sim_ctrl.power_strategy = 'predictive_opt';
                end
                fprintf('[SIM 3D] Switched Power Strategy to: %s\n', upper(sim_ctrl.power_strategy));
            case 'INJECT_FAULT'
                sim_ctrl.inject_fault = true;
                fprintf('[SIM 3D] Injected Over-Temperature Fault into Vehicle #1!\n');
            case 'CAM_ISO'
                if ~isempty(vis3d) && isvalid(vis3d.fig_handle); vis3d.set_camera_view(1); end
            case 'CAM_BAYS'
                if ~isempty(vis3d) && isvalid(vis3d.fig_handle); vis3d.set_camera_view(3); end
            case 'CAM_TOP'
                if ~isempty(vis3d) && isvalid(vis3d.fig_handle); vis3d.set_camera_view(2); end
        end
    end
end
