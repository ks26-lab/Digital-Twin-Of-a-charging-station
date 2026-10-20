function [state_next, OCV] = battery_model(state_curr, I_actual, dt, cfg)
% BATTERY_MODEL Discrete-time physical Li-ion battery pack simulation.
%
% Implements the electrochemical and thermal dynamics aligned directly with
% the Phase 1-10 Adaptive BMS V2.1 architecture:
%   1. Non-linear OCV(SOC) lookup via PCHIP interpolation
%   2. Multiphysics Internal Resistance Rint(SOC, SOH, T)
%   3. Lumped-parameter thermal balance: Cth*dT/dt = I^2*R - h*(T - Tamb)
%   4. Strict Coulomb-counting SOC integration: dSOC/dt = I / (3600*Q_nom)
%   5. Stress & temperature-accelerated SOH capacity degradation
%
% Inputs:
%   state_curr - Struct containing current battery state
%   I_actual   - Current delivered by the charger [A] (charging > 0)
%   dt         - Simulation update interval [s]
%   cfg        - Global configuration struct
%
% Outputs:
%   state_next - Struct with updated battery state variables
%   OCV        - Current Open-Circuit Voltage [V]

%% 1. Unpack Current States & Parameters
SOC   = state_curr.SOC;
SOH   = state_curr.SOH;
Temp  = state_curr.Temperature;
Q_nom = state_curr.Q_nom;
R_0   = state_curr.R_initial;

if isfield(state_curr, 'T_ambient') && ~isempty(state_curr.T_ambient)
    Tamb = state_curr.T_ambient;
else
    Tamb = cfg.battery.T_ambient;
end

if isfield(state_curr, 'V_max') && ~isempty(state_curr.V_max)
    V_max = state_curr.V_max;
else
    V_max = cfg.battery.V_max;
end

if isfield(state_curr, 'V_min') && ~isempty(state_curr.V_min)
    V_min = state_curr.V_min;
else
    V_min = cfg.battery.V_min;
end

Cth   = cfg.battery.Cth;
h     = cfg.battery.h_thermal;
deg_coeff = cfg.battery.degradation_coeff;

%% 2. Calculate Internal Resistance Rint (V2.1 Multiphysics Formulation)
% SOC Effect: Non-linear parabolic resistance rise at low/high SOC
soc_norm = abs(SOC - 0.5) / 0.5;
soc_factor = 1.0 + 0.30 * (soc_norm ^ 1.2);

% SOH Effect: SEI layer growth and active lithium loss increases resistance
soh_factor = 1.0 + 1.2 * max(0.0, 1.0 - SOH);

% Temperature Effect: Arrhenius-like kinetic conductivity increase with temperature
temp_factor = exp(-0.015 * (Temp - Tamb));
temp_factor = min(max(temp_factor, 0.75), 1.25); % Safety saturation bounds

Rint = R_0 * soc_factor * soh_factor * temp_factor;

%% 3. Open Circuit Voltage (OCV) Lookup
% Evaluated using verified Li-ion characteristic curve via PCHIP interpolation
OCV = interp1(cfg.battery.SOC_table, cfg.battery.OCV_table, SOC, 'pchip');

%% 4. Terminal Voltage Under Charging Current
% V_terminal = OCV + I*R (during charging, terminal voltage rises above OCV)
V_terminal = OCV + I_actual * Rint;

% Check over-voltage hardware trip condition
is_overvoltage = (V_terminal >= V_max);
if is_overvoltage
    V_terminal = min(V_terminal, V_max);
end

%% 5. Thermal Lumped-Parameter Dynamics
% Heat generation from Joule heating: P_loss = I^2 * Rint
heat_gen = (I_actual ^ 2) * Rint;

% Heat dissipation via Newton cooling: Q_loss = h * (T_cell - T_amb)
heat_loss = h * (Temp - Tamb);

% Net temperature derivative: dT/dt = (heat_gen - heat_loss) / Cth
dT_dt = (heat_gen - heat_loss) / Cth;
Temp_next = Temp + dT_dt * dt;
Temp_next = max(Temp_next, Tamb); % Convective cooling cannot drop below ambient

%% 6. Coulomb-Counting State of Charge (SOC) Integration
% dSOC = (I * dt) / (Q_nom * 3600)
dSOC = (I_actual * dt) / (Q_nom * 3600.0);
SOC_next = min(max(SOC + dSOC, 0.0), 1.0);

%% 7. Cycle State of Health (SOH) Capacity Degradation
% Accelerated by high temperature (>25 deg C) and quadratic C-rate stress
temp_deg_factor = 1.0 + 0.05 * max(Temp - Tamb, 0.0);
c_rate_instant = I_actual / max(Q_nom, 1.0);
c_rate_deg_factor = 1.0 + 0.50 * (c_rate_instant ^ 2);

degradation = deg_coeff * c_rate_deg_factor * temp_deg_factor * dt;
SOH_next = max(SOH - degradation, 0.0);

%% 8. Electrical Power and Energy Delivered
Power_W = V_terminal * I_actual;
energy_increment_kWh = (Power_W * dt) / 3.6e6;
energy_total_kWh = state_curr.energy_kWh + energy_increment_kWh;

%% 9. Pack Updated State
state_next = state_curr;
state_next.SOC = SOC_next;
state_next.SOH = SOH_next;
state_next.Temperature = Temp_next;
state_next.Rint = Rint;
state_next.Voltage = V_terminal;
state_next.Current = I_actual;
state_next.Power = Power_W;
state_next.energy_kWh = energy_total_kWh;
state_next.is_overvoltage = is_overvoltage;
state_next.is_overtemp = (Temp_next >= cfg.battery.T_trip);

end
