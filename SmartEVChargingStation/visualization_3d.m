classdef visualization_3d < handle
    % VISUALIZATION_3D High-fidelity 3D simulation renderer for the Smart EV
    % Charging Station using pure native MATLAB 3D graphics.
    %
    % Renders:
    %   - 3D asphalt terrain, lane markings, curbs, and bays
    %   - 4 distinct charging kiosks with active multi-color LED beacons
    %   - Dynamic 3D vehicle geometries with position/yaw transformations
    %   - 3D animated charging cables with catenary gravitational sag
    %   - Real-time vehicle telemetry billboard heads-up displays
    %   - 4 interactive camera perspectives (Isometric, Top-Down, Bays, Follow)
    
    properties
        fig_handle
        ax_handle
        cfg
        
        % Visual handles
        charger_kiosk_patches
        charger_led_patches
        charger_text_handles
        
        vehicle_transforms
        vehicle_body_patches
        vehicle_text_handles
        
        cable_line_handles
        plug_patch_handles
        
        camera_mode = 1; % 1: Overview, 2: Top-Down, 3: Bays Close-up, 4: Follow
        selected_vehicle_id = 1;
    end
    
    methods
        function obj = visualization_3d(cfg, fig)
            obj.cfg = cfg;
            if nargin < 2 || isempty(fig)
                obj.fig_handle = figure('Name', '3D Smart EV Charging Station Digital Twin', ...
                    'Color', [0.12, 0.14, 0.18], 'Position', [80, 60, 1100, 750]);
            else
                obj.fig_handle = fig;
            end
            
            clf(obj.fig_handle);
            obj.ax_handle = axes('Parent', obj.fig_handle, 'Color', [0.10, 0.12, 0.15]);
            hold(obj.ax_handle, 'on');
            grid(obj.ax_handle, 'on');
            axis(obj.ax_handle, 'equal');
            
            % Setup Lighting & Shading
            light(obj.ax_handle, 'Position', [20, -10, 40], 'Style', 'local');
            light(obj.ax_handle, 'Position', [10, 30, 20], 'Style', 'local', 'Color', [0.6, 0.6, 0.7]);
            lighting(obj.ax_handle, 'gouraud');
            
            % Build Static 3D Environment
            obj.build_station_environment();
            obj.build_charger_kiosks();
            
            % Initialize dynamic vehicle and cable handle arrays
            obj.vehicle_transforms   = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            obj.vehicle_body_patches = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            obj.vehicle_text_handles = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            
            obj.cable_line_handles = gobjects(cfg.charger.num_chargers, 1);
            obj.plug_patch_handles = gobjects(cfg.charger.num_chargers, 1);
            
            for i = 1:cfg.charger.num_chargers
                obj.cable_line_handles(i) = plot3(obj.ax_handle, [0, 0], [0, 0], [0, 0], ...
                    'LineWidth', 3.5, 'Color', [0.15, 0.15, 0.15], 'Visible', 'off');
                
                % 3D Plug connector indicator
                [px, py, pz] = cylinder(obj.ax_handle, 0.12, 8);
                obj.plug_patch_handles(i) = surf(obj.ax_handle, px, py, pz*0.2, ...
                    'FaceColor', [0.85, 0.45, 0.1], 'EdgeColor', 'none', 'Visible', 'off');
            end
            
            obj.set_camera_view(1);
        end
        
        function build_station_environment(obj)
            % 1. Main Asphalt Ground Slab
            L = obj.cfg.geo.station_length;
            W = obj.cfg.geo.station_width;
            
            patch(obj.ax_handle, [0, L, L, 0], [0, 0, W, W], [-0.05, -0.05, -0.05, -0.05], ...
                [0.18, 0.20, 0.24], 'EdgeColor', [0.25, 0.28, 0.32], 'FaceLighting', 'gouraud');
            
            % 2. Green Landscape Border
            patch(obj.ax_handle, [-5, L+5, L+5, -5], [-5, -5, 0, 0], [-0.06, -0.06, -0.06, -0.06], ...
                [0.12, 0.28, 0.16], 'EdgeColor', 'none');
            patch(obj.ax_handle, [-5, 0, 0, -5], [0, 0, W, W], [-0.06, -0.06, -0.06, -0.06], ...
                [0.12, 0.28, 0.16], 'EdgeColor', 'none');
            patch(obj.ax_handle, [L, L+5, L+5, L], [0, 0, W, W], [-0.06, -0.06, -0.06, -0.06], ...
                [0.12, 0.28, 0.16], 'EdgeColor', 'none');
            patch(obj.ax_handle, [-5, L+5, L+5, -5], [W, W, W+5, W+5], [-0.06, -0.06, -0.06, -0.06], ...
                [0.12, 0.28, 0.16], 'EdgeColor', 'none');
            
            % 3. Road Markings (White Driving Lane Lines)
            % Entrance Lane
            plot3(obj.ax_handle, [0, 32], [3, 3], [0.01, 0.01], '--', 'Color', [0.9, 0.9, 0.9], 'LineWidth', 2);
            % Circulation Lane
            plot3(obj.ax_handle, [32, 32], [3, 24], [0.01, 0.01], '--', 'Color', [0.9, 0.9, 0.9], 'LineWidth', 2);
            % Exit Lane
            plot3(obj.ax_handle, [32, 0], [24, 24], [0.01, 0.01], '--', 'Color', [0.9, 0.9, 0.9], 'LineWidth', 2);
            
            % 4. Delineate 4 Charging Bays
            for i = 1:length(obj.cfg.bays)
                bay = obj.cfg.bays(i);
                bw = obj.cfg.geo.bay_width;
                bl = obj.cfg.geo.bay_length;
                
                % Bay boundary box centered at bay.center
                x1 = bay.center(1) - bw/2 + 0.15;
                x2 = bay.center(1) + bw/2 - 0.15;
                y1 = bay.center(2) - bl/2;
                y2 = bay.center(2) + bl/2;
                
                % Green parking space asphalt inlay
                patch(obj.ax_handle, [x1, x2, x2, x1], [y1, y1, y2, y2], [0.005, 0.005, 0.005, 0.005], ...
                    [0.12, 0.26, 0.22], 'EdgeColor', [0.2, 0.85, 0.4], 'LineWidth', 2.5);
                
                % White bay boundary stripes
                plot3(obj.ax_handle, [x1, x1, x2, x2], [y2, y1, y1, y2], [0.015, 0.015, 0.015, 0.015], ...
                    'Color', [1.0, 1.0, 1.0], 'LineWidth', 2.5);
                
                % EV Charging Icon / Bay Number
                text(obj.ax_handle, bay.center(1), bay.center(2) + 1.8, 0.02, sprintf('BAY %d', bay.id), ...
                    'Color', [0.4, 0.9, 0.6], 'FontWeight', 'bold', 'FontSize', 10, ...
                    'HorizontalAlignment', 'center');
                
                % Wheel stop curb barrier
                patch(obj.ax_handle, [x1+0.4, x2-0.4, x2-0.4, x1+0.4], ...
                    [y1+0.6, y1+0.6, y1+0.85, y1+0.85], [0, 0, 0.15, 0.15], ...
                    [0.8, 0.8, 0.2], 'EdgeColor', [0.2, 0.2, 0.2]);
            end
            
            % Directional Road Arrows
            obj.draw_road_arrow([6, 3, 0.01], 0);
            obj.draw_road_arrow([22, 3, 0.01], 0);
            obj.draw_road_arrow([32, 14, 0.01], pi/2);
            obj.draw_road_arrow([22, 24, 0.01], pi);
            obj.draw_road_arrow([6, 24, 0.01], pi);
        end
        
        function draw_road_arrow(obj, pos, angle)
            % Simple white chevron arrow marking on pavement
            R = [cos(angle), -sin(angle); sin(angle), cos(angle)];
            pts = [-0.6, -0.3; 0.6, 0.0; -0.6, 0.3]';
            r_pts = R * pts;
            patch(obj.ax_handle, pos(1) + r_pts(1, :), pos(2) + r_pts(2, :), ...
                ones(1, 3)*pos(3), [0.95, 0.95, 0.95], 'EdgeColor', 'none');
        end
        
        function build_charger_kiosks(obj)
            % Instantiates 3D charger kiosks with LED status beacon lamps
            n = length(obj.cfg.bays);
            obj.charger_kiosk_patches = gobjects(n, 1);
            obj.charger_led_patches   = gobjects(n, 1);
            obj.charger_text_handles  = gobjects(n, 1);
            
            for i = 1:n
                pos = obj.cfg.bays(i).charger_pos;
                
                % 1. Kiosk Body (0.8m W x 0.6m D x 1.8m H)
                w = 0.8; d = 0.6; h = 1.8;
                [x, y, z] = obj.create_box_vertices(pos(1), pos(2), pos(3) + h/2, w, d, h);
                obj.charger_kiosk_patches(i) = patch(obj.ax_handle, 'Vertices', [x, y, z], ...
                    'Faces', obj.get_box_faces(), 'FaceColor', [0.25, 0.28, 0.35], ...
                    'EdgeColor', [0.4, 0.45, 0.55], 'FaceLighting', 'gouraud');
                
                % 2. LED Status Beacon on Top (Cylinder/Sphere)
                [lx, ly, lz] = sphere(obj.ax_handle, 10);
                r = 0.18;
                obj.charger_led_patches(i) = surf(obj.ax_handle, ...
                    pos(1) + lx*r, pos(2) + ly*r, pos(3) + h + lz*r + 0.1, ...
                    'FaceColor', [0.2, 0.85, 0.3], 'EdgeColor', 'none', ...
                    'AmbientStrength', 0.8, 'DiffuseStrength', 0.9);
                
                % 3. Digital LCD Screen / Text Display
                obj.charger_text_handles(i) = text(obj.ax_handle, pos(1), pos(2) + d/2 + 0.02, pos(3) + 1.3, ...
                    sprintf('CHG %d\nIDLE', i), 'Color', [0.2, 0.9, 1.0], 'FontWeight', 'bold', ...
                    'FontSize', 8, 'HorizontalAlignment', 'center', 'BackgroundColor', [0.05, 0.08, 0.12]);
            end
        end
        
        function render_vehicles(obj, vehicles)
            % Synchronize 3D vehicle geometries with fleet state
            active_ids = int32([vehicles.id]);
            
            % Remove departed vehicles
            existing_keys = obj.vehicle_transforms.keys;
            for k = 1:length(existing_keys)
                k_id = existing_keys{k};
                if ~ismember(k_id, active_ids)
                    delete(obj.vehicle_transforms(k_id));
                    delete(obj.vehicle_text_handles(k_id));
                    obj.vehicle_transforms.remove(k_id);
                    obj.vehicle_body_patches.remove(k_id);
                    obj.vehicle_text_handles.remove(k_id);
                end
            end
            
            % Update or instantiate each vehicle
            for i = 1:length(vehicles)
                veh = vehicles(i);
                k_id = int32(veh.id);
                
                if ~obj.vehicle_transforms.isKey(k_id)
                    % Create 3D vehicle geometry attached to a hgtransform
                    t_group = hgtransform('Parent', obj.ax_handle);
                    [body_patch] = obj.create_vehicle_mesh(t_group, veh);
                    
                    txt = text(obj.ax_handle, veh.position(1), veh.position(2), 2.2, ...
                        sprintf('EV #%d\n%s', veh.id, veh.state), ...
                        'Color', [1.0, 1.0, 1.0], 'FontWeight', 'bold', 'FontSize', 8, ...
                        'HorizontalAlignment', 'center', 'BackgroundColor', [0.1, 0.1, 0.15, 0.7]);
                    
                    obj.vehicle_transforms(k_id)   = t_group;
                    obj.vehicle_body_patches(k_id) = body_patch;
                    obj.vehicle_text_handles(k_id) = txt;
                end
                
                % Update Transform: Translation + Yaw Rotation
                t_group = obj.vehicle_transforms(k_id);
                T = makehgtform('translate', [veh.position(1), veh.position(2), 0.0], ...
                                'zrotate', veh.heading);
                set(t_group, 'Matrix', T);
                
                % Update HUD Billboard Text
                txt = obj.vehicle_text_handles(k_id);
                set(txt, 'Position', [veh.position(1), veh.position(2), 2.4]);
                
                if strcmpi(veh.state, "CHARGING")
                    txt_str = sprintf('EV #%d [%s]\nSOC: %.1f%% | I: %.1fA\nBSI: %.1f | T: %.1f°C', ...
                        veh.id, veh.charging_mode, veh.battery.SOC*100, veh.battery.Current, ...
                        veh.BSI, veh.battery.Temperature);
                else
                    txt_str = sprintf('EV #%d [%s]\nSOC: %.1f%%', veh.id, veh.state, veh.battery.SOC*100);
                end
                set(txt, 'String', txt_str);
            end
        end
        
        function render_cables(obj, connectors, bays, vehicles)
            % Renders 3D dynamic cables between chargers and connected vehicles
            for i = 1:length(connectors)
                conn = connectors(i);
                chg_id = conn.charger_id;
                
                if strcmpi(conn.state, "DISCONNECTED")
                    set(obj.cable_line_handles(chg_id), 'Visible', 'off');
                    set(obj.plug_patch_handles(chg_id), 'Visible', 'off');
                else
                    % Find assigned vehicle
                    v_idx = find([vehicles.assigned_bay] == conn.bay_id, 1);
                    if ~isempty(v_idx)
                        veh = vehicles(v_idx);
                        chg_pos = bays(conn.bay_id).charger_pos;
                        
                        [~, cable_pts, plug_p] = connector_manager.update_connector(...
                            conn, chg_pos, veh.position, veh.heading, veh.inlet_offset, 0.0, "HOLD");
                        
                        % Update 3D Cable spline
                        set(obj.cable_line_handles(chg_id), ...
                            'XData', cable_pts(:, 1), ...
                            'YData', cable_pts(:, 2), ...
                            'ZData', cable_pts(:, 3), ...
                            'Visible', 'on');
                        
                        % Update Plug Head
                        set(obj.plug_patch_handles(chg_id), ...
                            'XData', plug_p(1) + 0.08*randn(2, 9), ...
                            'YData', plug_p(2) + 0.08*randn(2, 9), ...
                            'ZData', plug_p(3) + 0.08*randn(2, 9), ...
                            'Visible', 'on');
                    end
                end
            end
        end
        
        function update_charger_indicators(obj, chargers)
            % Updates LED status lights and digital LCD panels on each kiosk
            for i = 1:length(chargers)
                chg = chargers(i);
                switch upper(chg.status)
                    case "AVAILABLE"
                        color = [0.2, 0.9, 0.3]; % Bright Green
                        status_str = "AVAILABLE";
                    case "RESERVED"
                        color = [1.0, 0.8, 0.1]; % Amber Yellow
                        status_str = "RESERVED";
                    case "CONNECTED"
                        color = [0.2, 0.6, 1.0]; % Cyan
                        status_str = "CONNECTED";
                    case "CHARGING"
                        color = [0.0, 0.95, 1.0]; % Electric Blue
                        status_str = sprintf('%.1f kW\n%.1f A', chg.P_out_kW, chg.I_out);
                    case "COMPLETE"
                        color = [0.85, 0.2, 0.85]; % Magenta
                        status_str = "COMPLETE";
                    case "FAULT"
                        color = [1.0, 0.15, 0.15]; % Red Alert
                        status_str = "FAULT";
                    otherwise
                        color = [0.5, 0.5, 0.5];
                        status_str = "STANDBY";
                end
                
                set(obj.charger_led_patches(i), 'FaceColor', color);
                set(obj.charger_text_handles(i), 'String', sprintf('CHG %d\n%s', chg.id, status_str));
            end
        end
        
        function set_camera_view(obj, mode, target_veh_pos)
            obj.camera_mode = mode;
            switch mode
                case 1 % Isometric Station Overview
                    view(obj.ax_handle, -38, 36);
                    camva(obj.ax_handle, 32);
                    campos(obj.ax_handle, [46, -16, 28]);
                    camtarget(obj.ax_handle, [20, 14, 0]);
                case 2 % Top-Down Overhead Map
                    view(obj.ax_handle, 0, 90);
                    camva(obj.ax_handle, 35);
                    campos(obj.ax_handle, [20, 15, 60]);
                    camtarget(obj.ax_handle, [20, 15, 0]);
                    camup(obj.ax_handle, [0, 1, 0]);
                case 3 % Close-Up Charging Bays View
                    view(obj.ax_handle, 0, 18);
                    camva(obj.ax_handle, 30);
                    campos(obj.ax_handle, [21, 2, 8]);
                    camtarget(obj.ax_handle, [21, 15, 1.2]);
                case 4 % Selected Vehicle Follow Cam
                    if nargin >= 3 && ~isempty(target_veh_pos)
                        campos(obj.ax_handle, [target_veh_pos(1)+8, target_veh_pos(2)-8, target_veh_pos(3)+6]);
                        camtarget(obj.ax_handle, [target_veh_pos(1), target_veh_pos(2), 1.0]);
                        camva(obj.ax_handle, 32);
                    end
            end
        end
        
        function [body_patch] = create_vehicle_mesh(obj, parent_transform, veh)
            % Constructs a sleek 3D vehicle body with wheels and windows
            L = veh.body_size(1);
            W = veh.body_size(2);
            H = veh.body_size(3);
            
            % Lower Chassis Box
            [x1, y1, z1] = obj.create_box_vertices(0, 0, H*0.35, L, W, H*0.45);
            body_patch = patch('Parent', parent_transform, 'Vertices', [x1, y1, z1], ...
                'Faces', obj.get_box_faces(), 'FaceColor', veh.color, ...
                'EdgeColor', [0.15, 0.15, 0.15], 'FaceLighting', 'gouraud');
            
            % Upper Cabin / Greenhouse
            [x2, y2, z2] = obj.create_box_vertices(-L*0.08, 0, H*0.75, L*0.55, W*0.82, H*0.45);
            patch('Parent', parent_transform, 'Vertices', [x2, y2, z2], ...
                'Faces', obj.get_box_faces(), 'FaceColor', [0.12, 0.18, 0.25], ...
                'EdgeColor', 'none', 'FaceAlpha', 0.85);
            
            % 4 Wheels (Cylinders)
            wheel_radius = 0.32;
            wheel_width  = 0.22;
            wx = [L*0.32, L*0.32, -L*0.32, -L*0.32];
            wy = [W*0.48, -W*0.48, W*0.48, -W*0.48];
            
            for w = 1:4
                [cyl_x, cyl_z, cyl_y] = cylinder(obj.ax_handle, wheel_radius, 12);
                cyl_y = cyl_y * wheel_width - wheel_width/2;
                surf('Parent', parent_transform, ...
                    cyl_x + wx(w), cyl_y + wy(w), cyl_z*wheel_radius + wheel_radius, ...
                    'FaceColor', [0.08, 0.08, 0.08], 'EdgeColor', 'none');
            end
            
            % Headlights (Front Bright White/Cyan)
            patch('Parent', parent_transform, ...
                'Vertices', [L/2+0.01,  W*0.3, H*0.35; ...
                             L/2+0.01,  W*0.15, H*0.35; ...
                             L/2+0.01,  W*0.15, H*0.48; ...
                             L/2+0.01,  W*0.3, H*0.48], ...
                'Faces', [1, 2, 3, 4], 'FaceColor', [0.9, 0.95, 1.0], 'EdgeColor', 'none', ...
                'AmbientStrength', 0.9);
            patch('Parent', parent_transform, ...
                'Vertices', [L/2+0.01, -W*0.3, H*0.35; ...
                             L/2+0.01, -W*0.15, H*0.35; ...
                             L/2+0.01, -W*0.15, H*0.48; ...
                             L/2+0.01, -W*0.3, H*0.48], ...
                'Faces', [1, 2, 3, 4], 'FaceColor', [0.9, 0.95, 1.0], 'EdgeColor', 'none', ...
                'AmbientStrength', 0.9);
        end
        
        function [X, Y, Z] = create_box_vertices(~, xc, yc, zc, lx, ly, lz)
            dx = lx / 2; dy = ly / 2; dz = lz / 2;
            X = [xc-dx; xc+dx; xc+dx; xc-dx; xc-dx; xc+dx; xc+dx; xc-dx];
            Y = [yc-dy; yc-dy; yc+dy; yc+dy; yc-dy; yc-dy; yc+dy; yc+dy];
            Z = [zc-dz; zc-dz; zc-dz; zc-dz; zc+dz; zc+dz; zc+dz; zc+dz];
        end
        
        function F = get_box_faces(~)
            F = [1, 2, 6, 5; ... % Front
                 2, 3, 7, 6; ... % Right
                 3, 4, 8, 7; ... % Back
                 4, 1, 5, 8; ... % Left
                 5, 6, 7, 8; ... % Top
                 1, 2, 3, 4];    % Bottom
        end
    end
end
