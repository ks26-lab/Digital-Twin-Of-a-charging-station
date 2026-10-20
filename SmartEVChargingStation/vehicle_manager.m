classdef vehicle_manager
    % VEHICLE_MANAGER Manages simulated EV fleet, kinematic motion,
    % autonomous waypoint navigation, and the 12-stage vehicle lifecycle.
    
    methods (Static)
        function veh = create_vehicle(varargin)
            % Instantiates a new vehicle with its unique battery & physical parameters.
            % Usage:
            %   veh = vehicle_manager.create_vehicle(v_cfg, cfg);
            %   veh = vehicle_manager.create_vehicle(id, template_idx, initial_SOC, target_SOC, initial_SOH, initial_Temp, cfg, custom_opts);
            
            if nargin == 2 && isstruct(varargin{1})
                v_cfg = varargin{1};
                cfg   = varargin{2};
                
                id           = v_cfg.id;
                template_idx = 2;
                if isfield(v_cfg, 'template_idx'); template_idx = v_cfg.template_idx; end
                initial_SOC  = v_cfg.initial_SOC;
                target_SOC   = v_cfg.target_SOC;
                initial_SOH  = v_cfg.initial_SOH;
                initial_Temp = v_cfg.initial_Temp;
                custom_opts  = v_cfg;
            else
                id           = varargin{1};
                template_idx = varargin{2};
                initial_SOC  = varargin{3};
                target_SOC   = varargin{4};
                initial_SOH  = varargin{5};
                initial_Temp = varargin{6};
                cfg          = varargin{7};
                custom_opts  = struct();
                if nargin >= 8; custom_opts = varargin{8}; end
            end
            
            tpl = cfg.fleet_templates(template_idx);
            
            veh.id           = id;
            veh.type_name    = tpl.type_name;
            if isfield(custom_opts, 'type_name'); veh.type_name = custom_opts.type_name; end
            veh.color        = tpl.color;
            veh.body_size    = tpl.body_size;       % [Length, Width, Height]
            veh.inlet_offset = tpl.inlet_offset;    % Offset from center
            veh.template_idx = template_idx;
            
            % Kinematic States
            veh.position     = cfg.geo.entrance_spawn;
            veh.heading      = 0.0;                 % Facing east along entrance lane
            veh.speed        = 0.0;
            veh.target_speed = cfg.motion.cruise_speed;
            
            % State Machine
            veh.state        = "ARRIVING";
            veh.assigned_bay = 0;
            veh.waypoints    = [cfg.geo.entrance_lane; cfg.geo.main_lane_turn; cfg.geo.circ_lane_top];
            veh.curr_wp_idx  = 1;
            
            % User enable/disable state
            veh.is_enabled   = true;
            if isfield(custom_opts, 'is_enabled'); veh.is_enabled = logical(custom_opts.is_enabled); end
            
            % Preserved initial conditions for reporting and reset
            veh.initial_SOC  = initial_SOC;
            veh.initial_SOH  = initial_SOH;
            veh.initial_Temp = initial_Temp;
            
            % Capacity, resistance, and limits
            Q_nom = tpl.Q_nom;
            if isfield(custom_opts, 'Q_nom') && ~isempty(custom_opts.Q_nom); Q_nom = custom_opts.Q_nom; end
            
            R_initial = tpl.R_initial;
            if isfield(custom_opts, 'R_initial') && ~isempty(custom_opts.R_initial); R_initial = custom_opts.R_initial; end
            veh.initial_Rint = R_initial;
            
            C_max = tpl.C_max;
            if isfield(custom_opts, 'C_max') && ~isempty(custom_opts.C_max); C_max = custom_opts.C_max; end
            
            T_ambient = cfg.battery.T_ambient;
            if isfield(custom_opts, 'T_ambient') && ~isempty(custom_opts.T_ambient); T_ambient = custom_opts.T_ambient; end
            
            V_min = cfg.battery.V_min;
            if isfield(custom_opts, 'V_min') && ~isempty(custom_opts.V_min); V_min = custom_opts.V_min; end
            
            V_max = cfg.battery.V_max;
            if isfield(custom_opts, 'V_max') && ~isempty(custom_opts.V_max); V_max = custom_opts.V_max; end
            
            I_max = cfg.charger.I_max;
            if isfield(custom_opts, 'I_max') && ~isempty(custom_opts.I_max); I_max = custom_opts.I_max; end
            
            % Independent Battery Model State
            veh.battery.SOC          = initial_SOC;
            veh.battery.target_SOC   = target_SOC;
            veh.battery.SOH          = initial_SOH;
            veh.battery.Temperature  = initial_Temp;
            veh.battery.T_ambient    = T_ambient;
            veh.battery.Q_nom        = Q_nom;
            veh.battery.R_initial    = R_initial;
            veh.battery.C_max        = C_max;
            veh.battery.V_min        = V_min;
            veh.battery.V_max        = V_max;
            veh.battery.I_max        = I_max;
            veh.battery.is_enabled   = veh.is_enabled;
            veh.battery.Rint         = R_initial;
            veh.battery.Voltage      = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, initial_SOC, 'pchip');
            veh.battery.Current      = 0.0;
            veh.battery.Power        = 0.0;
            veh.battery.energy_kWh   = 0.0;
            veh.battery.is_overvoltage = false;
            veh.battery.is_overtemp    = false;
            
            % BMS and Charging Controller State
            veh.prev_I_cmd   = 0.0;
            veh.I_cmd        = 0.0;
            veh.C_rate_cmd   = 0.0;
            veh.charging_mode= "STOP";
            veh.BSI          = 0.0;
            veh.bsi_data     = struct();
            veh.fault_msg    = "Normal";
            
            % Timers and Power Allocation Telemetry
            veh.time_in_state = 0.0;
            veh.total_charge_time = 0.0;
            veh.P_alloc_kW = 0.0;
            veh.P_delivered_kW = 0.0;
            veh.T_pred_sec = 0.0;
            veh.E_rem_kWh  = 0.0;
            veh.is_complete = false;
            veh.cycle_count = 100;
        end
        
        function veh = reset_vehicle(veh, cfg)
            % RESET_VEHICLE Restores vehicle to its initial user-configured state
            veh.position     = cfg.geo.entrance_spawn;
            veh.heading      = 0.0;
            veh.speed        = 0.0;
            veh.target_speed = cfg.motion.cruise_speed;
            veh.state        = "ARRIVING";
            veh.assigned_bay = 0;
            veh.waypoints    = [cfg.geo.entrance_lane; cfg.geo.main_lane_turn; cfg.geo.circ_lane_top];
            veh.curr_wp_idx  = 1;
            
            veh.battery.SOC          = veh.initial_SOC;
            veh.battery.SOH          = veh.initial_SOH;
            veh.battery.Temperature  = veh.initial_Temp;
            veh.battery.Rint         = veh.initial_Rint;
            veh.battery.Voltage      = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, veh.initial_SOC, 'pchip');
            veh.battery.Current      = 0.0;
            veh.battery.Power        = 0.0;
            veh.battery.energy_kWh   = 0.0;
            veh.battery.is_overvoltage = false;
            veh.battery.is_overtemp    = false;
            
            veh.prev_I_cmd   = 0.0;
            veh.I_cmd        = 0.0;
            veh.C_rate_cmd   = 0.0;
            veh.charging_mode= "STOP";
            veh.BSI          = 0.0;
            veh.bsi_data     = struct();
            veh.fault_msg    = "Normal";
            veh.time_in_state = 0.0;
            veh.total_charge_time = 0.0;
            veh.P_alloc_kW = 0.0;
            veh.P_delivered_kW = 0.0;
            veh.T_pred_sec = 0.0;
            veh.E_rem_kWh  = 0.0;
            veh.is_complete = false;
        end
        
        function [veh, bay_mgr_out] = update_vehicle(veh, bays, dt, mode_strategy, cfg)
            % Executes vehicle state machine and kinematic navigation
            bay_mgr_out = bays;
            veh.time_in_state = veh.time_in_state + dt;
            
            switch veh.state
                case "ARRIVING"
                    % Navigating entrance lane towards circulation lane
                    veh = vehicle_manager.navigate_waypoints(veh, dt, cfg);
                    
                    % Attempt to acquire an available charging bay
                    if veh.assigned_bay == 0
                        [bay_id, bay_mgr_out] = charging_bay_manager.request_bay(bays, veh.id);
                        if bay_id > 0
                            veh.assigned_bay = bay_id;
                            veh.state = "BAY_ASSIGNED";
                            veh.time_in_state = 0.0;
                            
                            % Re-route path directly to assigned bay's approach waypoint
                            bay_approach = bays(bay_id).approach;
                            veh.waypoints = [cfg.geo.main_lane_turn; cfg.geo.circ_lane_top; bay_approach];
                            veh.curr_wp_idx = 1;
                        end
                    end
                    
                case "BAY_ASSIGNED"
                    % Driving along circulation road to the assigned bay's approach point
                    veh = vehicle_manager.navigate_waypoints(veh, dt, cfg);
                    bay_approach = bays(veh.assigned_bay).approach;
                    
                    if norm(veh.position(1:2) - bay_approach(1:2)) <= cfg.motion.arrival_tolerance
                        veh.state = "APPROACHING_BAY";
                        veh.time_in_state = 0.0;
                        bay_center = bays(veh.assigned_bay).center;
                        veh.waypoints = [bay_center];
                        veh.curr_wp_idx = 1;
                        veh.target_speed = cfg.motion.parking_speed;
                    end
                    
                case "APPROACHING_BAY"
                    % Maneuvering into the bay
                    veh = vehicle_manager.navigate_waypoints(veh, dt, cfg);
                    bay_center = bays(veh.assigned_bay).center;
                    bay_heading = bays(veh.assigned_bay).orientation;
                    
                    is_aligned = charging_bay_manager.verify_parking(...
                        veh.position, veh.heading, bay_center, bay_heading, ...
                        cfg.motion.parking_tolerance, 0.25);
                    
                    if is_aligned || (norm(veh.position(1:2) - bay_center(1:2)) <= cfg.motion.parking_tolerance)
                        veh.position = bay_center;
                        veh.heading  = bay_heading;
                        veh.speed    = 0.0;
                        veh.state    = "PARKED";
                        veh.time_in_state = 0.0;
                        
                        % Lock bay occupancy in Bay Manager
                        bay_mgr_out = charging_bay_manager.set_bay_occupied(bays, veh.assigned_bay, veh.id);
                    end
                    
                case "PARKED"
                    veh.speed = 0.0;
                    % Pause briefly for parking verification then initiate connection
                    if veh.time_in_state >= 1.0
                        veh.state = "CONNECTING";
                        veh.time_in_state = 0.0;
                    end
                    
                case "CONNECTING"
                    veh.speed = 0.0;
                    % Connector Manager will transition vehicle to "CONNECTED" once locked
                    
                case "CONNECTED"
                    veh.speed = 0.0;
                    % Handshake completed, start charging
                    veh.state = "CHARGING";
                    veh.time_in_state = 0.0;
                    
                case "CHARGING"
                    veh.speed = 0.0;
                    veh.total_charge_time = veh.total_charge_time + dt;
                    
                    % Normal termination check: reached target SOC
                    if veh.battery.SOC >= veh.battery.target_SOC
                        veh.state = "CHARGING_COMPLETE";
                        veh.time_in_state = 0.0;
                    end
                    
                    % Fault check: over-temp or over-stress
                    if veh.battery.is_overtemp || veh.battery.is_overvoltage || veh.BSI >= cfg.bsi.trip_threshold
                        veh.state = "CHARGING_COMPLETE";
                        veh.fault_msg = "Safety Protection Interlock Tripped";
                        veh.time_in_state = 0.0;
                    end
                    
                case "CHARGING_COMPLETE"
                    veh.speed = 0.0;
                    % Hold for a moment to finalize session, then trigger disconnect
                    if veh.time_in_state >= 2.0
                        veh.state = "DISCONNECTING";
                        veh.time_in_state = 0.0;
                    end
                    
                case "DISCONNECTING"
                    veh.speed = 0.0;
                    % Connector Manager handles retraction
                    
                case "DEPARTING"
                    % Drive out of bay into circulation exit lane
                    veh = vehicle_manager.navigate_waypoints(veh, dt, cfg);
                    if veh.curr_wp_idx > size(veh.waypoints, 1) || ...
                       norm(veh.position(1:2) - cfg.geo.exit_gate(1:2)) <= 1.0
                        veh.state = "EXITED";
                        veh.time_in_state = 0.0;
                    end
            end
        end
        
        function veh = navigate_waypoints(veh, dt, cfg)
            % Autonomous kinematic steering towards current waypoint
            if isempty(veh.waypoints) || veh.curr_wp_idx > size(veh.waypoints, 1)
                veh.speed = 0.0;
                return;
            end
            
            target_wp = veh.waypoints(veh.curr_wp_idx, :);
            diff_vec  = target_wp(1:2) - veh.position(1:2);
            dist      = norm(diff_vec);
            
            if dist <= cfg.motion.arrival_tolerance
                % Waypoint reached, advance to next
                veh.curr_wp_idx = veh.curr_wp_idx + 1;
                if veh.curr_wp_idx > size(veh.waypoints, 1)
                    veh.speed = 0.0;
                    return;
                end
                target_wp = veh.waypoints(veh.curr_wp_idx, :);
                diff_vec  = target_wp(1:2) - veh.position(1:2);
            end
            
            % Desired Heading Angle
            desired_heading = atan2(diff_vec(2), diff_vec(1));
            
            % Smooth heading interpolation (turning rate limit)
            heading_err = atan2(sin(desired_heading - veh.heading), cos(desired_heading - veh.heading));
            turn_rate   = 3.0; % rad/s
            veh.heading = veh.heading + sign(heading_err) * min(abs(heading_err), turn_rate * dt);
            
            % Speed acceleration control
            accel = cfg.motion.max_accel;
            if veh.speed < veh.target_speed
                veh.speed = min(veh.speed + accel * dt, veh.target_speed);
            elseif veh.speed > veh.target_speed
                veh.speed = max(veh.speed - accel * dt, veh.target_speed);
            end
            
            % Update 2D/3D Position
            veh.position(1) = veh.position(1) + veh.speed * cos(veh.heading) * dt;
            veh.position(2) = veh.position(2) + veh.speed * sin(veh.heading) * dt;
            veh.position(3) = 0.0; % Ground plane
        end
    end
end
