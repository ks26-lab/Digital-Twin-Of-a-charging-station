function [cmd, bsi_data, fault] = bms_controller(battery_state, OCV, prev_I_cmd, dt, mode_strategy, target_SOC, cfg)
% BMS_CONTROLLER Battery Management System state estimator, BSI engine,
% and multi-stage adaptive C-rate charging controller.
%
% Implements:
%   1. Real-time Battery Stress Index (BSI) calculation
%   2. Multi-objective derating (Temperature, BSI, SOH, SOC)
%   3. Seamless Constant-Current to Constant-Voltage (CC-CV) transition
%   4. Fixed 1C vs Adaptive C-rate strategy selection
%   5. Dynamic hardware slew-rate limiting (A/s)
%   6. Comprehensive fault detection (Over-temp, Over-voltage, High BSI)
%
% Inputs:
%   battery_state - Current battery state struct
%   OCV           - Open circuit voltage [V]
%   prev_I_cmd    - Commanded current from previous time step [A]
%   dt            - Time step [s]
%   mode_strategy - 'adaptive' or 'fixed'
%   target_SOC    - Target termination SOC (typically 0.85 - 0.95)
%   cfg           - System configuration struct
%
% Outputs:
%   cmd      - Struct with commanded current, C-rate, mode ("CC"/"CV"/"STOP")
%   bsi_data - Struct with BSI components and derating factors
%   fault    - Struct with active fault flags and status message

%% 1. Unpack Parameters
SOC   = battery_state.SOC;
SOH   = battery_state.SOH;
Temp  = battery_state.Temperature;
Rint  = battery_state.Rint;
Q_nom = battery_state.Q_nom;
R_0   = battery_state.R_initial;
C_max = battery_state.C_max;

% Per-vehicle configuration overrides with global fallbacks
if isfield(battery_state, 'T_ambient') && ~isempty(battery_state.T_ambient)
    Tamb = battery_state.T_ambient;
else
    Tamb = cfg.battery.T_ambient;
end

if isfield(battery_state, 'V_max') && ~isempty(battery_state.V_max)
    V_max = battery_state.V_max;
else
    V_max = cfg.battery.V_max;
end

if isfield(battery_state, 'I_max') && ~isempty(battery_state.I_max)
    I_max = battery_state.I_max;
else
    I_max = cfg.charger.I_max;
end

T_warn = cfg.battery.T_warning;
T_trip = cfg.battery.T_trip;

fault.active = false;
fault.code   = "NONE";
fault.msg    = "Normal Operation";

% Check User Enable/Disable State
is_enabled = true;
if isfield(battery_state, 'is_enabled')
    is_enabled = battery_state.is_enabled;
end

if ~is_enabled
    cmd.I_cmd = 0.0;
    cmd.C_rate_cmd = 0.0;
    cmd.mode = "STOP";
    cmd.C_target = 0.0;
    bsi_data.BSI = 0.0;
    bsi_data.stress_C = 0.0;
    bsi_data.stress_T = 0.0;
    bsi_data.stress_SOC = 0.0;
    bsi_data.stress_R = 0.0;
    bsi_data.stress_SOH = 0.0;
    bsi_data.tempFactor = 1.0;
    bsi_data.bsiFactor = 1.0;
    bsi_data.sohFactor = 1.0;
    fault.active = false;
    fault.code   = "DISABLED";
    fault.msg    = "Vehicle Charging Disabled by User";
    return;
end

%% 2. Calculate Battery Stress Index (BSI)
% C-rate stress: ratio of instantaneous rate to maximum design rate
actual_C_rate = abs(prev_I_cmd) / max(Q_nom, 1.0);
stress_C = min(actual_C_rate / C_max, 1.0);

% Thermal stress: normalized rise between Tamb and trip limit
stress_T = min(max((Temp - Tamb) / (T_trip - Tamb), 0.0), 1.0);

% SOC stress: electro-chemical intercalation stress at high saturation
if SOC < 0.50
    stress_SOC = 0.10;
elseif SOC < 0.70
    stress_SOC = 0.30;
elseif SOC < 0.85
    stress_SOC = 0.55;
elseif SOC < 0.95
    stress_SOC = 0.85;
else
    stress_SOC = 1.00;
end

% Internal resistance degradation stress
stress_R = min(max((Rint / R_0 - 1.0) / 0.50, 0.0), 1.0);

% SOH capacity fade stress (relative to 30% end-of-life threshold)
stress_SOH = min(max((1.0 - SOH) / 0.30, 0.0), 1.0);

% Weighted Composite BSI Score [0 - 100]
BSI = 100.0 * (cfg.bsi.wC   * stress_C + ...
               cfg.bsi.wT   * stress_T + ...
               cfg.bsi.wSOC * stress_SOC + ...
               cfg.bsi.wR   * stress_R + ...
               cfg.bsi.wSOH * stress_SOH);
BSI = min(max(BSI, 0.0), 100.0);

%% 3. Safety Guardrails & Critical Fault Checks
if Temp >= T_trip
    fault.active = true;
    fault.code   = "ERR_OVER_TEMP";
    fault.msg    = sprintf("Critical Temperature: %.1f C >= %.1f C", Temp, T_trip);
    C_target     = 0.0;
elseif BSI >= cfg.bsi.trip_threshold
    fault.active = true;
    fault.code   = "ERR_OVER_STRESS";
    fault.msg    = sprintf("Critical Battery Stress Index: %.1f >= %.1f", BSI, cfg.bsi.trip_threshold);
    C_target     = 0.0;
elseif OCV >= V_max
    % Reached chemical voltage saturation limit
    C_target = 0.0;
    fault.msg = "Pack Voltage Reached Upper Cutoff Limit";
elseif SOC >= target_SOC
    % Normal charging completion
    C_target = 0.0;
    fault.msg = "Target State of Charge Achieved";
else
    %% 4. Charging Strategy Selection (Adaptive vs Fixed 1C)
    if strcmpi(mode_strategy, 'fixed')
        % Fixed 1.0C Charging Mode
        base_C     = 1.0;
        tempFactor = 1.0;
        bsiFactor  = 1.0;
        sohFactor  = 1.0;
        C_target   = min(base_C, C_max);
    else
        % --- STRESS-AWARE ADAPTIVE C-RATE CONTROLLER ---
        
        % 4.1 SOC-Dependent Base C-rate
        if SOC < 0.50
            base_C = 1.5;
        elseif SOC < 0.70
            base_C = 1.2;
        elseif SOC < 0.85
            base_C = 0.9;
        elseif SOC < 0.90
            base_C = 0.7;
        else
            base_C = 0.6;
        end
        
        % 4.2 Multi-stage Temperature Derating Factor
        if Temp < 28.0
            tempFactor = 1.00;
        elseif Temp < 30.0
            tempFactor = 0.90;
        elseif Temp < 32.0
            tempFactor = 0.75;
        elseif Temp < 35.0
            tempFactor = 0.55;
        elseif Temp < T_warn
            tempFactor = 0.35;
        else
            tempFactor = 0.20;
        end
        
        % 4.3 Multi-stage BSI Stress Derating Factor
        if BSI < 35.0
            bsiFactor = 1.00;
        elseif BSI < cfg.bsi.warning_threshold
            bsiFactor = 0.90;
        elseif BSI < cfg.bsi.high_threshold
            bsiFactor = 0.75;
        elseif BSI < cfg.bsi.trip_threshold
            bsiFactor = 0.50;
        else
            bsiFactor = 0.00;
        end
        
        % 4.4 SOH Capacity Preservation Factor
        if SOH >= 0.90
            sohFactor = 1.00;
        elseif SOH >= 0.85
            sohFactor = 0.90;
        elseif SOH >= 0.80
            sohFactor = 0.80;
        else
            sohFactor = 0.60;
        end
        
        % 4.5 Composite Adaptive C-Rate
        C_temp = base_C * tempFactor;
        C_bsi  = base_C * bsiFactor;
        C_soh  = base_C * sohFactor;
        
        C_target = min([base_C, C_temp, C_bsi, C_soh, C_max]);
        C_target = max(C_target, 0.0);
    end
end

% 4.6 Proactive Predictive Analytics Throttling (if provided)
if isfield(battery_state, 'C_max_advice') && ~isempty(battery_state.C_max_advice)
    C_target = min(C_target, battery_state.C_max_advice);
end

if ~exist('tempFactor', 'var'); tempFactor = 1.0; end
if ~exist('bsiFactor', 'var');  bsiFactor  = 1.0; end
if ~exist('sohFactor', 'var');  sohFactor  = 1.0; end

%% 5. Constant Current (CC) & Constant Voltage (CV) Clamping
% CC current clamped by battery and user-specified continuous I_max
I_CC = min(C_target * Q_nom, I_max);

% CV upper limit: Current required to keep terminal voltage at V_max
I_CV = (V_max - OCV) / max(Rint, 1.0e-4);
I_CV = max(I_CV, 0.0);

% Charger current reference is minimum of CC demand, CV boundary, and I_max
I_desired = min([I_CC, I_CV, I_max]);

%% 6. Current Slew-Rate Limiting
max_dI = cfg.charger.slew_rate * dt;
if I_desired > prev_I_cmd + max_dI
    I_cmd = prev_I_cmd + max_dI;
elseif I_desired < prev_I_cmd - max_dI
    I_cmd = prev_I_cmd - max_dI;
else
    I_cmd = I_desired;
end
I_cmd = max(I_cmd, 0.0);

%% 7. Operational Mode Classification
if I_cmd <= 0.05
    op_mode = "STOP";
elseif I_CV < I_CC
    op_mode = "CV";
else
    op_mode = "CC";
end

%% 8. Pack Output Structures
cmd.I_cmd = I_cmd;
cmd.C_rate_cmd = I_cmd / max(Q_nom, 1.0);
cmd.mode = op_mode;
cmd.C_target = C_target;

bsi_data.BSI = BSI;
bsi_data.stress_C = stress_C;
bsi_data.stress_T = stress_T;
bsi_data.stress_SOC = stress_SOC;
bsi_data.stress_R = stress_R;
bsi_data.stress_SOH = stress_SOH;
bsi_data.tempFactor = tempFactor;
bsi_data.bsiFactor = bsiFactor;
bsi_data.sohFactor = sohFactor;

end
