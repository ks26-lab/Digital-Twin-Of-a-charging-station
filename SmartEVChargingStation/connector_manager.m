classdef connector_manager
    % CONNECTOR_MANAGER Manages the 3-tier vehicle-to-charger connection:
    %   1. Visual: Computes 3D animated cable splines and connector transforms
    %   2. Logical: Tracks handshake state machine and session timestamps
    %   3. Electrical: Controls the hardware contactor interlock signal
    
    methods (Static)
        function conn = init_connector(charger_id, bay_id)
            % Initialize connector state for a specific charging bay
            conn.charger_id = charger_id;
            conn.bay_id     = bay_id;
            conn.vehicle_id = 0;
            conn.session_id = 0;
            
            % State: "DISCONNECTED", "EXTENDING", "LOCKED", "RETRACTING"
            conn.state      = "DISCONNECTED";
            conn.progress   = 0.0; % Animation interpolation [0.0 to 1.0]
            conn.electrical_connected = false;
            
            conn.t_connect_start = 0.0;
            conn.t_connected     = 0.0;
            conn.t_disconnect    = 0.0;
        end
        
        function [conn, cable_points, plug_pos] = update_connector(conn, charger_pos, vehicle_pos, vehicle_heading, inlet_offset, dt, command)
            % Updates the 3D connector state and computes realistic 3D cable geometry
            %
            % command: "CONNECT", "DISCONNECT", "HOLD"
            
            speed = 0.5; % Cable extension speed (progress/second, full lock in ~2s)
            
            % 1. State Transitions
            switch conn.state
                case "DISCONNECTED"
                    conn.progress = 0.0;
                    conn.electrical_connected = false;
                    if strcmpi(command, "CONNECT")
                        conn.state = "EXTENDING";
                    end
                    
                case "EXTENDING"
                    conn.progress = conn.progress + speed * dt;
                    if conn.progress >= 1.0
                        conn.progress = 1.0;
                        conn.state = "LOCKED";
                        conn.electrical_connected = true; % Electrical interlock closed
                    end
                    
                case "LOCKED"
                    conn.progress = 1.0;
                    conn.electrical_connected = true;
                    if strcmpi(command, "DISCONNECT")
                        conn.state = "RETRACTING";
                        conn.electrical_connected = false; % Open electrical contactor immediately
                    end
                    
                case "RETRACTING"
                    conn.electrical_connected = false;
                    conn.progress = conn.progress - speed * dt;
                    if conn.progress <= 0.0
                        conn.progress = 0.0;
                        conn.state = "DISCONNECTED";
                        conn.vehicle_id = 0;
                    end
            end
            
            % 2. Calculate 3D World Positions
            % Charger nozzle holder (located 1.4m above ground on kiosk front)
            p_charger = charger_pos(:) + [0.0; 0.6; 1.4];
            
            % Vehicle inlet position (transformed from body coordinates to world coordinates)
            % Rotation matrix around Z-axis (Yaw)
            R = [cos(vehicle_heading), -sin(vehicle_heading), 0;
                 sin(vehicle_heading),  cos(vehicle_heading), 0;
                 0,                     0,                    1];
             
            p_inlet = vehicle_pos(:) + R * inlet_offset(:);
            
            % 3. Current Plug Position based on extension progress
            % Interpolate between charger dock and vehicle inlet
            plug_pos = (1.0 - conn.progress) * p_charger + conn.progress * p_inlet;
            
            % 4. 3D Cable Spline with realistic catenary sag
            % Generate smooth 3D points between charger and plug
            num_pts = 15;
            t = linspace(0, 1, num_pts)';
            
            cable_points = zeros(num_pts, 3);
            for i = 1:num_pts
                u = t(i);
                % Base linear interpolation
                base_pt = (1.0 - u) * p_charger' + u * plug_pos';
                
                % Catenary gravitational droop (parabolic sag curve)
                sag_max = 0.45 * (1.0 - abs(u - 0.5) * 2.0) * conn.progress;
                base_pt(3) = base_pt(3) - sag_max;
                base_pt(3) = max(base_pt(3), 0.05); % Prevent clipping through ground
                
                cable_points(i, :) = base_pt;
            end
        end
    end
end
