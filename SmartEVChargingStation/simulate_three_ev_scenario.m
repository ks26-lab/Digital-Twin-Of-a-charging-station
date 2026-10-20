function sim_log = simulate_three_ev_scenario(scen_cfg, global_cfg)
% SIMULATE_THREE_EV_SCENARIO High-fidelity, closed-loop simulation of the 3-EV
% dynamic arrival, BMS verification, and power reallocation scenario.
%
% Accurately models the complete sequence:
%   Stage A: EVs 1 and 2 charging under initial station power allocation.
%   Stage B: EV 3 physically connects at t_connect. Station detects connection.
%   Stage C: BMS verification pending (t_connect <= t < t_verify).
%            EV 3 strictly receives 0.0 A current. Contactor remains open.
%   Stage D: BMS verification succeeds at t_verify (or fails if fault injected).
%            Only upon authorization does EV 3 receive power allocation and current.
%            Existing EV 1 & 2 currents are throttled dynamically if P_station requires it.
%   Stage E: Closed-loop electro-thermal feedback updates SOC, voltage, temp, and BSI.
%
% Usage:
%   sim_log = simulate_three_ev_scenario(); % Default scenario
%   sim_log = simulate_three_ev_scenario(custom_scen_cfg);

if nargin < 2 || isempty(global_cfg)
    global_cfg = station_config();
end

%% 1. Default Scenario Configuration
if nargin < 1 || isempty(scen_cfg)
    scen_cfg = struct();
end

% Timing parameters
if ~isfield(scen_cfg, 't_connect');    scen_cfg.t_connect    = 60.0;  end % EV 3 connects at 60s
if ~isfield(scen_cfg, 't_verify');     scen_cfg.t_verify     = 80.0;  end % BMS verified at 80s (20s handshake)
if ~isfield(scen_cfg, 't_end');        scen_cfg.t_end        = 240.0; end % Duration: 240s
if ~isfield(scen_cfg, 'dt');           scen_cfg.dt           = 0.5;   end % 0.5s step
if ~isfield(scen_cfg, 'P_station');    scen_cfg.P_station    = 10.0;  end % 10 kW station budget
if ~isfield(scen_cfg, 'strategy');     scen_cfg.strategy     = 'predictive_opt'; end
if ~isfield(scen_cfg, 'bms_strategy'); scen_cfg.bms_strategy = 'adaptive'; end
if ~isfield(scen_cfg, 'realloc_policy'); scen_cfg.realloc_policy = 'on_authorization'; end % 'on_authorization' or 'on_connection'

% EV 1 Configuration (Standard Sedan: 50 Ah, 70% Initial SOC)
if ~isfield(scen_cfg, 'ev1')
    scen_cfg.ev1.id = 1;
    scen_cfg.ev1.type_name = 'Standard Sedan EV';
    scen_cfg.ev1.template_idx = 2;
    scen_cfg.ev1.Q_nom = 50.0;
    scen_cfg.ev1.initial_SOC = 0.70;
    scen_cfg.ev1.target_SOC = 0.90;
    scen_cfg.ev1.initial_SOH = 0.96;
    scen_cfg.ev1.initial_Temp = 25.0;
    scen_cfg.ev1.T_ambient = 25.0;
    scen_cfg.ev1.R_initial = 0.050;
    scen_cfg.ev1.C_max = 1.5;
    scen_cfg.ev1.V_min = 40.0;
    scen_cfg.ev1.V_max = 54.6;
    scen_cfg.ev1.I_max = 85.0;
    scen_cfg.ev1.is_enabled = true;
end

% EV 2 Configuration (Standard Sedan: 50 Ah, 80% Initial SOC)
if ~isfield(scen_cfg, 'ev2')
    scen_cfg.ev2.id = 2;
    scen_cfg.ev2.type_name = 'Compact City EV';
    scen_cfg.ev2.template_idx = 1;
    scen_cfg.ev2.Q_nom = 40.0;
    scen_cfg.ev2.initial_SOC = 0.80;
    scen_cfg.ev2.target_SOC = 0.90;
    scen_cfg.ev2.initial_SOH = 0.98;
    scen_cfg.ev2.initial_Temp = 25.0;
    scen_cfg.ev2.T_ambient = 25.0;
    scen_cfg.ev2.R_initial = 0.055;
    scen_cfg.ev2.C_max = 1.5;
    scen_cfg.ev2.V_min = 40.0;
    scen_cfg.ev2.V_max = 54.6;
    scen_cfg.ev2.I_max = 85.0;
    scen_cfg.ev2.is_enabled = true;
end

% EV 3 Configuration (Arrival Vehicle: Configurable SOC, e.g., 70% or 20%)
if ~isfield(scen_cfg, 'ev3')
    scen_cfg.ev3.id = 3;
    scen_cfg.ev3.type_name = 'Fleet Cargo Van';
    scen_cfg.ev3.template_idx = 3;
    scen_cfg.ev3.Q_nom = 65.0;
    scen_cfg.ev3.initial_SOC = 0.70;
    scen_cfg.ev3.target_SOC = 0.90;
    scen_cfg.ev3.initial_SOH = 0.94;
    scen_cfg.ev3.initial_Temp = 26.0;
    scen_cfg.ev3.T_ambient = 25.0;
    scen_cfg.ev3.R_initial = 0.042;
    scen_cfg.ev3.C_max = 1.3;
    scen_cfg.ev3.V_min = 40.0;
    scen_cfg.ev3.V_max = 54.6;
    scen_cfg.ev3.I_max = 85.0;
    scen_cfg.ev3.is_enabled = true;
end

% Fault Injection Options for EV 3
if ~isfield(scen_cfg, 'ev3_inject_fault'); scen_cfg.ev3_inject_fault = false; end
if ~isfield(scen_cfg, 'ev3_fault_type');   scen_cfg.ev3_fault_type = 'ERR_OVER_TEMP'; end % or 'ERR_OVER_VOLT', 'ERR_BMS_DIS'

%% 2. System Initialization
dt = scen_cfg.dt;
cfg = global_cfg;
cfg.station.grid_power_limit = scen_cfg.P_station;
cfg.station.strategy = scen_cfg.strategy;

% Instantiate Vehicles
v1 = vehicle_manager.create_vehicle(scen_cfg.ev1, cfg);
v2 = vehicle_manager.create_vehicle(scen_cfg.ev2, cfg);
v3 = vehicle_manager.create_vehicle(scen_cfg.ev3, cfg);

% Vehicle 1 and 2 start connected and charging in Bays 1 and 2
v1.state = "CHARGING"; v1.assigned_bay = 1;
v2.state = "CHARGING"; v2.assigned_bay = 2;

% Vehicle 3 starts disconnected
v3.state = "ARRIVING"; v3.assigned_bay = 0;

vehicles = [v1, v2, v3];

% Initialize Chargers (3 active kiosks)
chargers = repmat(struct(), 3, 1);
for i = 1:3
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
end
chargers(1).status = "CHARGING";
chargers(2).status = "CHARGING";

% Initialize Connectors & Verification States
% Status: "DISCONNECTED", "PHYSICAL_CONNECTED", "PENDING_VERIFICATION", "AUTHORIZED", "REJECTED"
conn_state = ["LOCKED", "LOCKED", "DISCONNECTED"];
bms_auth   = ["AUTHORIZED", "AUTHORIZED", "NOT_CONNECTED"];
fault_msg  = ["Normal", "Normal", "None"];

connectors = repmat(struct(), 3, 1);
for i = 1:3
    connectors(i) = connector_manager.init_connector(i, i);
    if i <= 2
        connectors(i).state = "LOCKED";
        connectors(i).electrical_connected = true;
    end
end

% Predictive Model Object
pred_model = predictive_analytics.get_model();

%% 3. Pre-allocate High-Resolution Time-Series Logger
N_steps = floor(scen_cfg.t_end / dt) + 1;

log.time            = zeros(N_steps, 1);
log.P_station_limit = ones(N_steps, 1) * scen_cfg.P_station;
log.P_station_total = zeros(N_steps, 1);

% 5 Current levels per vehicle: [Requested, BMS_Approved, Allocated, Commanded, Delivered]
log.I_requested  = zeros(N_steps, 3);
log.I_bms_appr   = zeros(N_steps, 3);
log.I_allocated  = zeros(N_steps, 3);
log.I_commanded  = zeros(N_steps, 3);
log.I_delivered  = zeros(N_steps, 3);

log.P_allocated  = zeros(N_steps, 3);
log.P_delivered  = zeros(N_steps, 3);

log.SOC          = zeros(N_steps, 3);
log.Voltage      = zeros(N_steps, 3);
log.Temperature  = zeros(N_steps, 3);
log.BSI          = zeros(N_steps, 3);
log.Energy_kWh   = zeros(N_steps, 3);

log.conn_state   = strings(N_steps, 3);
log.bms_auth     = strings(N_steps, 3);
log.fault_reason = strings(N_steps, 3);

log.event_markers = {}; % Stores timestamped milestones

%% 4. Master Discrete-Time Simulation Loop
step_idx = 1;
sim_time = 0.0;

while sim_time <= scen_cfg.t_end
    
    %% --- EVENT STAGE LOGIC: EV 3 LIFECYCLE ---
    if sim_time >= scen_cfg.t_connect && strcmpi(conn_state(3), "DISCONNECTED")
        % STAGE B: EV 3 Physically Connects
        conn_state(3) = "PHYSICAL_CONNECTED";
        bms_auth(3)   = "PENDING_VERIFICATION";
        vehicles(3).state = "CONNECTED";
        vehicles(3).assigned_bay = 3;
        chargers(3).status = "CONNECTED";
        connectors(3).state = "LOCKED";
        % Note: Contactors remain open until authorized:
        connectors(3).electrical_connected = false;
        
        log.event_markers{end+1} = struct('time', sim_time, ...
            'event', 'EV3_PHYSICAL_CONNECT', ...
            'desc', sprintf('EV3 Cable Locked in Bay 3 at t=%.1fs. BMS Verification Pending.', sim_time));
    end
    
    if sim_time >= scen_cfg.t_verify && strcmpi(bms_auth(3), "PENDING_VERIFICATION")
        % STAGE D / E: BMS Verification Handshake Decision
        if scen_cfg.ev3_inject_fault
            % STAGE E: Verification Fails
            bms_auth(3)   = "REJECTED";
            conn_state(3) = "REJECTED";
            connectors(3).electrical_connected = false;
            chargers(3).fault_active = true;
            chargers(3).status = "FAULT";
            
            if strcmpi(scen_cfg.ev3_fault_type, 'ERR_OVER_TEMP')
                vehicles(3).battery.Temperature = 46.5; % 46.5 C >= 45 C trip limit
                fault_msg(3) = "ERR_OVER_TEMP: Battery Temperature 46.5 C >= 45.0 C Trip Limit";
            elseif strcmpi(scen_cfg.ev3_fault_type, 'ERR_OVER_VOLT')
                vehicles(3).battery.Voltage = 56.0; % > 54.6 V limit
                fault_msg(3) = "ERR_OVER_VOLT: Battery Voltage 56.0 V >= 54.6 V Limit";
            else
                vehicles(3).is_enabled = false;
                fault_msg(3) = "ERR_BMS_DIS: Vehicle BMS Charging Disabled by User";
            end
            
            log.event_markers{end+1} = struct('time', sim_time, ...
                'event', 'EV3_BMS_REJECTED', ...
                'desc', sprintf('EV3 BMS Check FAILED at t=%.1fs (%s). Zero current authorized.', sim_time, fault_msg(3)));
        else
            % STAGE D: Verification Passes
            bms_auth(3)   = "AUTHORIZED";
            conn_state(3) = "LOCKED";
            connectors(3).electrical_connected = true; % Close electrical contactor
            vehicles(3).state = "CHARGING";
            chargers(3).status = "CHARGING";
            
            log.event_markers{end+1} = struct('time', sim_time, ...
                'event', 'EV3_BMS_AUTHORIZED', ...
                'desc', sprintf('EV3 BMS Verified at t=%.1fs. All checks passed. Power reallocated.', sim_time));
        end
    end
    
    %% --- STEP 1: EVALUATE BATTERY ELECTROCHEMISTRY & OCV ---
    OCV_arr = zeros(3, 1);
    for i = 1:3
        OCV_arr(i) = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, vehicles(i).battery.SOC, 'pchip');
    end
    
    %% --- STEP 2: EVALUATE BMS CONTROLLER & SAFE CHARGING BOUNDS ---
    I_requested_step = zeros(3, 1);
    I_bms_appr_step  = zeros(3, 1);
    bsi_step         = zeros(3, 1);
    
    for i = 1:3
        veh = vehicles(i);
        
        % Unconstrained requested current (from base design C-rate)
        I_requested_step(i) = veh.battery.C_max * veh.battery.Q_nom;
        
        % Check authorization gating
        if ~strcmpi(bms_auth(i), "AUTHORIZED")
            I_bms_appr_step(i) = 0.0;
            bsi_step(i) = 0.0;
        else
            % Proactive predictive AI advisory
            [~, ~, C_max_adv, ~] = predictive_analytics.forecast(pred_model, veh.battery, 100, cfg);
            veh.battery.C_max_advice = C_max_adv;
            
            % Execute verified BMS controller
            [bms_cmd, bsi_data, fault] = bms_controller(...
                veh.battery, OCV_arr(i), veh.prev_I_cmd, dt, scen_cfg.bms_strategy, veh.battery.target_SOC, cfg);
            
            I_bms_appr_step(i) = bms_cmd.I_cmd;
            bsi_step(i) = bsi_data.BSI;
            if fault.active
                fault_msg(i) = fault.msg;
            end
        end
    end
    
    %% --- STEP 3: STATION-LEVEL POWER ALLOCATION ---
    % Build eligibility list based on contactor & authorization policy
    elig_connectors = connectors;
    if strcmpi(scen_cfg.realloc_policy, 'on_authorization')
        % EV 3 is eligible for station grid power ONLY after BMS authorization:
        for i = 1:3
            if ~strcmpi(bms_auth(i), "AUTHORIZED")
                elig_connectors(i).electrical_connected = false;
            end
        end
    else
        % 'on_connection': station reserves power on physical connection, but contactor blocks current
        for i = 1:3
            if strcmpi(conn_state(i), "DISCONNECTED") || strcmpi(bms_auth(i), "REJECTED")
                elig_connectors(i).electrical_connected = false;
            end
        end
    end
    
    [P_alloc_step, ~, ~] = station_power_allocator.allocate_power(...
        vehicles, chargers, elig_connectors, scen_cfg.strategy, cfg);
    
    %% --- STEP 4: CONVERT ALLOCATED POWER TO FEASIBLE CURRENT & COMMAND ---
    I_allocated_step = zeros(3, 1);
    I_commanded_step = zeros(3, 1);
    I_delivered_step = zeros(3, 1);
    P_delivered_step = zeros(3, 1);
    
    for i = 1:3
        veh = vehicles(i);
        is_contact_closed = connectors(i).electrical_connected && strcmpi(bms_auth(i), "AUTHORIZED");
        
        % Feasible current allowed by allocated power: P = V * I => I = (P * 1000) / V
        V_term_est = max(veh.battery.Voltage, 36.0);
        I_allocated_step(i) = (P_alloc_step(i) * 1000.0) / V_term_est;
        
        if ~is_contact_closed || ~veh.is_enabled || veh.battery.SOC >= veh.battery.target_SOC
            I_target_cmd = 0.0;
        else
            % Commanded current is the minimum of BMS-approved safety limit and Station Grid allocation
            I_target_cmd = min(I_bms_appr_step(i), I_allocated_step(i));
        end
        
        % Slew rate limiter (10 A/s) to prevent inductive/converter transient spikes
        max_dI = cfg.charger.slew_rate * dt;
        if I_target_cmd > veh.prev_I_cmd + max_dI
            I_commanded_step(i) = veh.prev_I_cmd + max_dI;
        elseif I_target_cmd < veh.prev_I_cmd - max_dI
            I_commanded_step(i) = veh.prev_I_cmd - max_dI;
        else
            I_commanded_step(i) = I_target_cmd;
        end
        I_commanded_step(i) = max(I_commanded_step(i), 0.0);
        
        % Pass through charger converter model
        [chargers(i), I_deliv, P_elec_kW, ~] = charger_model(...
            chargers(i), I_commanded_step(i), veh.battery.Voltage, is_contact_closed, P_alloc_step(i), dt, cfg);
        
        I_delivered_step(i) = I_deliv;
        P_delivered_step(i) = P_elec_kW;
        
        %% --- STEP 5: CLOSED-LOOP CURRENT FEEDBACK INTO BATTERY MODEL ---
        [veh.battery, ~] = battery_model(veh.battery, I_deliv, dt, cfg);
        veh.prev_I_cmd = I_deliv;
        veh.P_alloc_kW = P_alloc_step(i);
        veh.P_delivered_kW = P_elec_kW;
        veh.BSI = bsi_step(i);
        
        vehicles(i) = veh;
    end
    
    %% --- STEP 6: LOGGING ---
    if step_idx <= N_steps
        log.time(step_idx)              = sim_time;
        log.P_station_total(step_idx)   = sum(P_delivered_step);
        
        log.I_requested(step_idx, :)    = I_requested_step';
        log.I_bms_appr(step_idx, :)     = I_bms_appr_step';
        log.I_allocated(step_idx, :)    = I_allocated_step';
        log.I_commanded(step_idx, :)    = I_commanded_step';
        log.I_delivered(step_idx, :)    = I_delivered_step';
        
        log.P_allocated(step_idx, :)    = P_alloc_step';
        log.P_delivered(step_idx, :)    = P_delivered_step';
        
        for k = 1:3
            log.SOC(step_idx, k)         = vehicles(k).battery.SOC * 100.0;
            log.Voltage(step_idx, k)     = vehicles(k).battery.Voltage;
            log.Temperature(step_idx, k) = vehicles(k).battery.Temperature;
            log.BSI(step_idx, k)         = vehicles(k).BSI;
            log.Energy_kWh(step_idx, k)  = vehicles(k).battery.energy_kWh;
        end
        
        log.conn_state(step_idx, :)   = conn_state;
        log.bms_auth(step_idx, :)     = bms_auth;
        log.fault_reason(step_idx, :) = fault_msg;
        
        step_idx = step_idx + 1;
    end
    
    sim_time = sim_time + dt;
end

% Trim logs to actual steps executed
valid_len = step_idx - 1;
log.time            = log.time(1:valid_len);
log.P_station_limit = log.P_station_limit(1:valid_len);
log.P_station_total = log.P_station_total(1:valid_len);
log.I_requested     = log.I_requested(1:valid_len, :);
log.I_bms_appr      = log.I_bms_appr(1:valid_len, :);
log.I_allocated     = log.I_allocated(1:valid_len, :);
log.I_commanded     = log.I_commanded(1:valid_len, :);
log.I_delivered     = log.I_delivered(1:valid_len, :);
log.P_allocated     = log.P_allocated(1:valid_len, :);
log.P_delivered     = log.P_delivered(1:valid_len, :);
log.SOC             = log.SOC(1:valid_len, :);
log.Voltage         = log.Voltage(1:valid_len, :);
log.Temperature     = log.Temperature(1:valid_len, :);
log.BSI             = log.BSI(1:valid_len, :);
log.Energy_kWh      = log.Energy_kWh(1:valid_len, :);
log.conn_state      = log.conn_state(1:valid_len, :);
log.bms_auth        = log.bms_auth(1:valid_len, :);
log.fault_reason    = log.fault_reason(1:valid_len, :);

log.scen_cfg = scen_cfg;
sim_log = log;

end
