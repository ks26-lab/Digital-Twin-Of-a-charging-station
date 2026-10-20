function [charger_state, I_actual, P_elec_kW, P_grid_kW] = charger_model(charger_state, I_cmd, V_battery, is_connected, power_alloc_kW, dt, cfg)
% CHARGER_MODEL Physical and electrical model of an individual DC Fast Charger kiosk.
%
% Features:
%   1. Hardware voltage and continuous current boundary enforcement
%   2. Strict electrical interlock: I_out = 0 if disconnected or faulted
%   3. Dynamic power throttling via station-level grid allocation
%   4. Power converter efficiency modeling (AC Grid Power vs DC Delivered)
%   5. Energy delivery accumulation per charging session
%
% Inputs:
%   charger_state - Struct containing current charger kiosk status
%   I_cmd         - Commanded charging current from vehicle BMS [A]
%   V_battery     - Real-time battery terminal voltage [V]
%   is_connected  - Physical & electrical connector interlock status (bool)
%   power_alloc_kW- Maximum power permitted by station grid manager [kW]
%   dt            - Time step [s]
%   cfg           - System configuration struct
%
% Outputs:
%   charger_state - Struct with updated internal states and telemetry
%   I_actual      - True current delivered into the battery terminals [A]
%   P_elec_kW     - DC electrical output power [kW]
%   P_grid_kW     - AC grid input power consumed [kW]

%% 1. Default Safe Output Values
I_actual   = 0.0;
P_elec_kW  = 0.0;
P_grid_kW  = 0.0;

%% 2. Electrical Interlock and Safety Gate
% If connector is not physically locked, or charger is faulted, NO CURRENT FLOWS
if ~is_connected || charger_state.fault_active || strcmpi(charger_state.status, "FAULT")
    charger_state.I_out = 0.0;
    charger_state.V_out = 0.0;
    charger_state.P_out_kW = 0.0;
    return;
end

%% 3. Hardware Boundary Constraints
% Respect maximum continuous current rating of the power converter
I_feasible = min(max(I_cmd, 0.0), cfg.charger.I_max);

% Maximum power available to this charger (lesser of kiosk rating and grid allocation)
P_cap_kW = min(cfg.charger.P_max, power_alloc_kW);

% Ensure battery voltage is within charger operating window
if V_battery > cfg.charger.V_max
    % Exceeds charger hardware voltage envelope
    charger_state.fault_active = true;
    charger_state.status = "FAULT";
    charger_state.fault_msg = "Over-voltage envelope violation";
    return;
elseif V_battery < cfg.charger.V_min
    % Pack deeply depleted below charger pre-charge sensing limit
    I_feasible = min(I_feasible, 5.0); % Safe pre-charge trickle current
end

%% 4. Power Saturation Clamping
% P = V * I. If requested power exceeds allocated capacity, throttle current:
P_requested_kW = (V_battery * I_feasible) / 1000.0;

if P_requested_kW > P_cap_kW && V_battery > 0.1
    I_actual = (P_cap_kW * 1000.0) / V_battery;
    P_elec_kW = P_cap_kW;
else
    I_actual = I_feasible;
    P_elec_kW = P_requested_kW;
end

%% 5. Grid Power and Efficiency
P_grid_kW = P_elec_kW / max(cfg.charger.efficiency, 0.1);

%% 6. Accumulate Energy Delivered
energy_increment_kWh = (P_elec_kW * dt) / 3600.0;
charger_state.energy_delivered_kWh = charger_state.energy_delivered_kWh + energy_increment_kWh;

%% 7. Update Charger State Telemetry
charger_state.I_out = I_actual;
charger_state.V_out = V_battery;
charger_state.P_out_kW = P_elec_kW;
charger_state.P_grid_kW = P_grid_kW;

if I_actual > 0.1
    charger_state.status = "CHARGING";
else
    if is_connected
        charger_state.status = "CONNECTED";
    end
end

end
