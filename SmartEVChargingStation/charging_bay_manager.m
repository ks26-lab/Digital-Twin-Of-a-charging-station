classdef charging_bay_manager
    % CHARGING_BAY_MANAGER Manages charging bay states, allocation,
    % reservation, occupancy tracking, and geometric parking validation.
    
    methods (Static)
        function bays = init_bays(cfg)
            % Initialize all physical charging bays from configuration
            num_bays = length(cfg.bays);
            bays = repmat(struct(), num_bays, 1);
            
            for i = 1:num_bays
                bays(i).id = cfg.bays(i).id;
                bays(i).center = cfg.bays(i).center;
                bays(i).approach = cfg.bays(i).approach;
                bays(i).charger_pos = cfg.bays(i).charger_pos;
                bays(i).orientation = cfg.bays(i).orientation;
                bays(i).status = "AVAILABLE"; % "AVAILABLE", "RESERVED", "OCCUPIED", "FAULTED"
                bays(i).assigned_vehicle_id = 0;
                bays(i).charger_id = i;
            end
        end
        
        function [bay_id, bays] = request_bay(bays, vehicle_id)
            % Atomically allocate an available bay to an arriving vehicle
            bay_id = 0;
            for i = 1:length(bays)
                if strcmpi(bays(i).status, "AVAILABLE")
                    bays(i).status = "RESERVED";
                    bays(i).assigned_vehicle_id = vehicle_id;
                    bay_id = bays(i).id;
                    return;
                end
            end
        end
        
        function bays = set_bay_occupied(bays, bay_id, vehicle_id)
            % Confirm vehicle is physically parked and occupying the bay
            idx = [bays.id] == bay_id;
            if any(idx)
                bays(idx).status = "OCCUPIED";
                bays(idx).assigned_vehicle_id = vehicle_id;
            end
        end
        
        function bays = release_bay(bays, bay_id)
            % Release bay upon vehicle departure
            idx = [bays.id] == bay_id;
            if any(idx)
                bays(idx).status = "AVAILABLE";
                bays(idx).assigned_vehicle_id = 0;
            end
        end
        
        function is_parked = verify_parking(vehicle_pos, vehicle_heading, bay_center, bay_heading, tol_pos, tol_heading)
            % Verify vehicle has parked inside tolerances
            dist_error = norm(vehicle_pos(1:2) - bay_center(1:2));
            
            % Angle difference wrapped to [-pi, pi]
            angle_error = abs(atan2(sin(vehicle_heading - bay_heading), cos(vehicle_heading - bay_heading)));
            
            is_parked = (dist_error <= tol_pos) && (angle_error <= tol_heading);
        end
    end
end
