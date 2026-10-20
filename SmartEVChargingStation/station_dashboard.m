classdef station_dashboard < handle
    % STATION_DASHBOARD Master Interactive Digital Twin Dashboard and Telemetry
    % System for the 3D Smart EV Fast Charging Station.
    %
    % Core Capabilities (Sections 2, 3, 5, 8):
    %   1. Direct User Configuration Deck:
    %      - Station: Grid limit (kW), Active vehicles (1-4), Power strategy, BMS strategy, Duration, dt
    %      - Per-Vehicle Editable Inputs: Capacity (Ah), Initial & Target SOC, SOH, Initial & Ambient Temp,
    %        Internal Resistance (Ohm), Max C-rate, Voltage limits [V_min, V_max], Current limit (I_max),
    %        Charging Enable/Disable toggle.
    %   2. Rigid Input Validation Engine:
    %      - Enforces physical bounds, dependencies (target_SOC > init_SOC, V_max > V_min), units.
    %      - Rejects invalid configurations and prevents them from reaching the simulation engine.
    %   3. Complete Live Digital Twin Telemetry:
    %      - Per-Vehicle: Initial & Current SOC, SOH, V_term, Current, Temp, Rint, BSI, Mode (CC/CV/STOP),
    %        Allocated Power, Delivered Power, Energy Delivered, Predicted Time Remaining, Status & Faults.
    %      - Station-Wide: Total capacity & grid load, per-vehicle power distribution, makespan T_finish,
    %        energy injected, multi-strategy comparative metrics.
    %   4. 6 Synchronized Real-Time Rolling Time-Series Graphs:
    %      - SOC (%), Current (A), Terminal Voltage (V), Temp (deg C), Power (kW), BSI (0-100).
    %   5. Interactive Simulation Control:
    %      - [APPLY INPUTS], [START/RESUME], [PAUSE], [RESET INITIAL CONDITIONS], [COMPARE STRATEGIES].
    
    properties
        fig_handle
        cfg
        is_headless = false
        
        % Active Configuration Structures
        user_station_cfg
        user_vehicle_cfg
        
        % GUI State
        selected_edit_veh_id = 1
        monitored_veh_id     = 1
        sim_state            = "STOPPED"  % "STOPPED", "RUNNING", "PAUSED"
        action_callback                   % Function handle for simulation coordinator
        
        % Station Config UI Controls
        edit_station_power
        pop_num_vehicles
        pop_power_strategy
        pop_bms_strategy
        edit_duration
        edit_dt
        
        % Vehicle Config UI Controls
        pop_veh_edit_select
        edit_q_nom
        edit_init_soc
        edit_target_soc
        edit_init_soh
        edit_init_temp
        edit_ambient_temp
        edit_r_initial
        edit_c_max
        edit_v_min
        edit_v_max
        edit_i_max
        chk_veh_enabled
        lbl_validation_status
        
        % Control Buttons
        btn_start_pause
        btn_apply_inputs
        btn_reset
        btn_compare
        
        % Station Telemetry Text Displays
        txt_station_grid_load
        txt_station_energy
        txt_station_makespan
        txt_bay_status
        txt_power_breakdown
        
        % Selected Vehicle Telemetry Text Displays
        pop_veh_monitor_select
        txt_veh_header
        txt_veh_soc
        txt_veh_health
        txt_veh_elec
        txt_veh_thermal
        txt_veh_bsi
        txt_veh_power
        txt_veh_status
        
        % 6 Synchronized Rolling Plots
        ax_soc;     line_soc;     line_target_soc
        ax_current; line_current; line_i_cmd
        ax_voltage; line_voltage
        ax_temp;    line_temp
        ax_power;   line_power_alloc; line_power_deliv
        ax_bsi;     line_bsi
        
        % Rolling History Buffers
        history_time        = []
        history_soc         = []
        history_target_soc  = []
        history_curr_deliv  = []
        history_curr_cmd    = []
        history_voltage     = []
        history_temp        = []
        history_power_alloc = []
        history_power_deliv = []
        history_bsi         = []
    end
    
    methods
        function obj = station_dashboard(cfg, fig, is_headless)
            % CONSTRUCTOR
            obj.cfg = cfg;
            if nargin >= 3
                obj.is_headless = is_headless;
            end
            
            % Initialize default configurations from cfg
            obj.user_station_cfg.grid_power_limit = cfg.station.grid_power_limit;
            obj.user_station_cfg.num_vehicles     = 4;
            obj.user_station_cfg.power_strategy   = cfg.station.strategy;
            obj.user_station_cfg.bms_strategy     = 'adaptive';
            obj.user_station_cfg.duration         = cfg.sim.max_time;
            obj.user_station_cfg.dt               = cfg.sim.dt;
            
            obj.user_vehicle_cfg = cfg.default_user_vehicles;
            
            if ~obj.is_headless
                if nargin < 2 || isempty(fig)
                    obj.fig_handle = figure('Name', 'BMS & Station Digital Twin Interactive Dashboard', ...
                        'Color', [0.10, 0.12, 0.16], 'Position', [80, 50, 1150, 920], ...
                        'NumberTitle', 'off', 'MenuBar', 'none');
                else
                    obj.fig_handle = fig;
                end
                clf(obj.fig_handle);
                obj.setup_interactive_layout();
            end
        end
        
        function setup_interactive_layout(obj)
            % Builds clean, organized two-deck GUI: Left = Config & Controls, Right = Live Telemetry & Plots
            
            %% 1. Master Title Bar
            uicontrol('Parent', obj.fig_handle, 'Style', 'text', ...
                'Position', [15, 875, 1120, 35], ...
                'String', 'SMART DC FAST CHARGING STATION - DIGITAL TWIN CONTROL DECK', ...
                'FontSize', 14, 'FontWeight', 'bold', ...
                'ForegroundColor', [0.25, 0.90, 0.65], 'BackgroundColor', [0.14, 0.17, 0.22]);
            
            %% 2. LEFT COLUMN: USER INPUT & CONFIGURATION DECK (Width = 360 px)
            p_cfg = uipanel('Parent', obj.fig_handle, 'Title', '  SIMULATION & BATTERY USER INPUTS  ', ...
                'Position', [0.015, 0.02, 0.33, 0.92], ...
                'ForegroundColor', [0.3, 0.85, 1.0], 'BackgroundColor', [0.12, 0.15, 0.20], ...
                'FontSize', 10, 'FontWeight', 'bold');
            
            % --- 2.1 Station Level Parameters ---
            y = 780;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 340, 20], ...
                'String', '--- STATION PARAMETERS ---', 'FontWeight', 'bold', ...
                'ForegroundColor', [0.95, 0.80, 0.20], 'BackgroundColor', [0.12, 0.15, 0.20]);
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Max Station Power (kW):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_station_power = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 160, 22], 'String', num2str(obj.user_station_cfg.grid_power_limit), ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Active Vehicles (1-4):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.pop_num_vehicles = uicontrol('Parent', p_cfg, 'Style', 'popupmenu', ...
                'Position', [180, y, 160, 22], 'String', {'1 Vehicle', '2 Vehicles', '3 Vehicles', '4 Vehicles'}, ...
                'Value', obj.user_station_cfg.num_vehicles, ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Power Alloc Strategy:', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.pop_power_strategy = uicontrol('Parent', p_cfg, 'Style', 'popupmenu', ...
                'Position', [180, y, 160, 22], ...
                'String', {'Predictive Min-Max (Opt)', 'Energy-Aware', 'Equal Share'}, ...
                'Value', 1, 'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'BMS Charging Strategy:', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.pop_bms_strategy = uicontrol('Parent', p_cfg, 'Style', 'popupmenu', ...
                'Position', [180, y, 160, 22], 'String', {'Stress-Aware Adaptive C-Rate', 'Fixed 1.0C Benchmark'}, ...
                'Value', 1, 'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Sim Duration (s) / dt (s):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_duration = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 75, 22], 'String', num2str(obj.user_station_cfg.duration), ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            obj.edit_dt = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [265, y, 75, 22], 'String', num2str(obj.user_station_cfg.dt), ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            % --- 2.2 Per-Vehicle Battery Parameters ---
            y = y - 36;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 340, 20], ...
                'String', '--- PER-VEHICLE BATTERY CONFIGURATION ---', 'FontWeight', 'bold', ...
                'ForegroundColor', [0.25, 0.90, 0.65], 'BackgroundColor', [0.12, 0.15, 0.20]);
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Select Vehicle Profile:', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.pop_veh_edit_select = uicontrol('Parent', p_cfg, 'Style', 'popupmenu', ...
                'Position', [180, y, 160, 22], ...
                'String', {'Vehicle #1 (Sedan)', 'Vehicle #2 (City EV)', 'Vehicle #3 (Delivery Van)', 'Vehicle #4 (Executive EV)'}, ...
                'Value', 1, 'BackgroundColor', [0.22, 0.28, 0.38], 'ForegroundColor', [0.4, 0.9, 1.0], ...
                'Callback', @(~,~) obj.on_vehicle_selection_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Capacity Q_nom (Ah):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_q_nom = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 160, 22], 'String', '50.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Initial & Target SOC (%):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_init_soc = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 75, 22], 'String', '25.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            obj.edit_target_soc = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [265, y, 75, 22], 'String', '90.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Initial SOH (%):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_init_soh = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 160, 22], 'String', '96.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Initial & Amb Temp (°C):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_init_temp = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 75, 22], 'String', '25.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            obj.edit_ambient_temp = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [265, y, 75, 22], 'String', '25.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Initial Internal R (Ω):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_r_initial = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 160, 22], 'String', '0.050', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Max Permitted C-Rate (h⁻¹):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_c_max = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 160, 22], 'String', '1.5', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Voltage Limits [Vmin, Vmax]:', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_v_min = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 75, 22], 'String', '40.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            obj.edit_v_max = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [265, y, 75, 22], 'String', '54.6', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 28;
            uicontrol('Parent', p_cfg, 'Style', 'text', 'Position', [10, y, 160, 20], ...
                'String', 'Current Limit I_max (A):', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.12, 0.15, 0.20]);
            obj.edit_i_max = uicontrol('Parent', p_cfg, 'Style', 'edit', ...
                'Position', [180, y, 160, 22], 'String', '85.0', ...
                'BackgroundColor', [0.18, 0.22, 0.30], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_input_changed());
            
            y = y - 30;
            obj.chk_veh_enabled = uicontrol('Parent', p_cfg, 'Style', 'checkbox', ...
                'Position', [15, y, 320, 24], ...
                'String', ' Vehicle Charging Session Enabled', 'Value', 1, ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'ForegroundColor', [0.4, 0.9, 0.5], 'BackgroundColor', [0.12, 0.15, 0.20], ...
                'Callback', @(~,~) obj.on_input_changed());
            
            % Validation Status Feedback
            y = y - 45;
            obj.lbl_validation_status = uicontrol('Parent', p_cfg, 'Style', 'text', ...
                'Position', [10, y, 335, 40], ...
                'String', 'Configuration Status: Validated & Ready', ...
                'FontSize', 9, 'FontWeight', 'bold', ...
                'ForegroundColor', [0.3, 0.9, 0.5], 'BackgroundColor', [0.15, 0.19, 0.25]);
            
            % --- 2.3 Action Pushbuttons ---
            y = y - 45;
            obj.btn_apply_inputs = uicontrol('Parent', p_cfg, 'Style', 'pushbutton', ...
                'Position', [10, y, 335, 34], 'String', 'APPLY USER INPUTS TO DIGITAL TWIN', ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.15, 0.55, 0.85], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_action_clicked('APPLY_INPUTS'));
            
            y = y - 42;
            obj.btn_start_pause = uicontrol('Parent', p_cfg, 'Style', 'pushbutton', ...
                'Position', [10, y, 160, 34], 'String', 'START SIMULATION', ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.18, 0.70, 0.35], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_action_clicked('TOGGLE_PLAY'));
            
            obj.btn_reset = uicontrol('Parent', p_cfg, 'Style', 'pushbutton', ...
                'Position', [185, y, 160, 34], 'String', 'RESET INITIAL COND', ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.80, 0.30, 0.25], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_action_clicked('RESET'));
            
            y = y - 42;
            obj.btn_compare = uicontrol('Parent', p_cfg, 'Style', 'pushbutton', ...
                'Position', [10, y, 335, 34], 'String', 'COMPARE ALL 3 ALLOCATION STRATEGIES', ...
                'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.70, 0.40, 0.85], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_action_clicked('COMPARE_STRATEGIES'));
            
            %% 3. RIGHT COLUMN: LIVE TELEMETRY CARDS & 6 TIME-SERIES PLOTS
            % Telemetry Deck: y in [530, 860], plots in [30, 510]
            
            % --- 3.1 Station Telemetry Card ---
            p_station_tel = uipanel('Parent', obj.fig_handle, 'Title', '  STATION GRID & OPTIMIZATION TELEMETRY  ', ...
                'Position', [0.36, 0.73, 0.625, 0.21], ...
                'ForegroundColor', [0.2, 0.85, 1.0], 'BackgroundColor', [0.13, 0.16, 0.22], ...
                'FontSize', 10, 'FontWeight', 'bold');
            
            obj.txt_station_grid_load = uicontrol('Parent', p_station_tel, 'Style', 'text', ...
                'Position', [15, 120, 320, 24], 'String', 'Grid Demand: 0.00 kW / 14.0 kW (0.0%)', ...
                'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [0.2, 0.9, 1.0], 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_station_energy = uicontrol('Parent', p_station_tel, 'Style', 'text', ...
                'Position', [350, 120, 330, 24], 'String', 'Total Energy Delivered: 0.000 kWh', ...
                'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [0.4, 0.9, 0.4], 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_station_makespan = uicontrol('Parent', p_station_tel, 'Style', 'text', ...
                'Position', [15, 85, 320, 24], 'String', 'Predicted Station Completion: 0.0 min', ...
                'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [1.0, 0.8, 0.2], 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_bay_status = uicontrol('Parent', p_station_tel, 'Style', 'text', ...
                'Position', [350, 85, 330, 24], 'String', 'Bays: 4 Available | 0 Occupied', ...
                'FontSize', 10, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_power_breakdown = uicontrol('Parent', p_station_tel, 'Style', 'text', ...
                'Position', [15, 15, 660, 55], ...
                'String', 'Power Distribution: Bay 1: 0.0 kW | Bay 2: 0.0 kW | Bay 3: 0.0 kW | Bay 4: 0.0 kW\nStrategy: Predictive Makespan Min-Max | Solver: Bisection Water-Filling', ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [0.85, 0.85, 0.85], 'BackgroundColor', [0.15, 0.19, 0.26]);
            
            % --- 3.2 Vehicle Telemetry Card ---
            p_veh_tel = uipanel('Parent', obj.fig_handle, 'Title', '  SELECTED VEHICLE REAL-TIME BMS DIAGNOSTICS  ', ...
                'Position', [0.36, 0.46, 0.625, 0.25], ...
                'ForegroundColor', [0.3, 0.9, 0.6], 'BackgroundColor', [0.13, 0.16, 0.22], ...
                'FontSize', 10, 'FontWeight', 'bold');
            
            uicontrol('Parent', p_veh_tel, 'Style', 'text', 'Position', [15, 160, 110, 20], ...
                'String', 'Live Vehicle Feed:', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.13, 0.16, 0.22]);
            obj.pop_veh_monitor_select = uicontrol('Parent', p_veh_tel, 'Style', 'popupmenu', ...
                'Position', [130, 160, 200, 22], ...
                'String', {'Vehicle #1', 'Vehicle #2', 'Vehicle #3', 'Vehicle #4'}, ...
                'Value', 1, 'BackgroundColor', [0.20, 0.25, 0.35], 'ForegroundColor', 'w', ...
                'Callback', @(~,~) obj.on_monitor_selection_changed());
            
            obj.txt_veh_header = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [345, 160, 340, 22], 'String', 'Vehicle #1: Not Connected', ...
                'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [0.3, 0.85, 1.0], 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_veh_soc = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [15, 125, 320, 22], 'String', 'SOC: Init 25.0% -> Current 25.0% (Target 90.0%)', ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_veh_health = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [345, 125, 340, 22], 'String', 'SOH: 96.0% | Rint: 0.050 Ω | Q_nom: 50.0 Ah', ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_veh_elec = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [15, 95, 320, 22], 'String', 'Terminal Volt: 43.5 V | Current: 0.0 A (Cmd 0.0 A)', ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_veh_thermal = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [345, 95, 340, 22], 'String', 'Cell Temp: 25.0 °C (Amb 25.0 °C) | Trip: 45.0 °C', ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_veh_power = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [15, 65, 320, 22], 'String', 'Power: Alloc 0.00 kW | Deliv 0.00 kW | Energy: 0.00 kWh', ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', 'w', 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_veh_bsi = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [345, 65, 340, 22], 'String', 'Battery Stress Index: 0.0 / 100 (Safe)', ...
                'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [0.95, 0.70, 0.20], 'BackgroundColor', [0.13, 0.16, 0.22]);
            
            obj.txt_veh_status = uicontrol('Parent', p_veh_tel, 'Style', 'text', ...
                'Position', [15, 15, 670, 40], ...
                'String', 'Mode: STOP | C-Rate: 0.00 C | Time Rem: 0.0 min | Protection: All Systems Normal\nPredictive Analytics: Baseline Physics Model Ready', ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [0.4, 0.9, 0.6], 'BackgroundColor', [0.15, 0.19, 0.26]);
            
            % --- 3.3 6 Real-Time Rolling Telemetry Subplots ---
            % Grid layout: 3 rows x 2 cols in bottom area
            pos_x1 = 0.39; pos_x2 = 0.69;
            w = 0.28; h = 0.10;
            
            % Plot 1: SOC vs Time
            obj.ax_soc = axes('Parent', obj.fig_handle, 'Position', [pos_x1, 0.32, w, h], ...
                'Color', [0.12, 0.15, 0.20], 'XColor', [0.6, 0.6, 0.7], 'YColor', [0.6, 0.6, 0.7]);
            hold(obj.ax_soc, 'on');
            obj.line_soc = plot(obj.ax_soc, 0, 0, 'Color', [0.2, 0.85, 0.4], 'LineWidth', 2);
            obj.line_target_soc = plot(obj.ax_soc, [0, 100], [90, 90], '--r', 'LineWidth', 1);
            title(obj.ax_soc, 'State of Charge (%)', 'Color', [0.85, 0.85, 0.85], 'FontSize', 8);
            grid(obj.ax_soc, 'on'); ylim(obj.ax_soc, [0, 100]);
            
            % Plot 2: Current vs Time
            obj.ax_current = axes('Parent', obj.fig_handle, 'Position', [pos_x2, 0.32, w, h], ...
                'Color', [0.12, 0.15, 0.20], 'XColor', [0.6, 0.6, 0.7], 'YColor', [0.6, 0.6, 0.7]);
            hold(obj.ax_current, 'on');
            obj.line_current = plot(obj.ax_current, 0, 0, 'Color', [0.2, 0.75, 1.0], 'LineWidth', 2);
            obj.line_i_cmd   = plot(obj.ax_current, 0, 0, '--y', 'LineWidth', 1);
            title(obj.ax_current, 'Delivered Current vs Command (A)', 'Color', [0.85, 0.85, 0.85], 'FontSize', 8);
            grid(obj.ax_current, 'on');
            
            % Plot 3: Terminal Voltage vs Time
            obj.ax_voltage = axes('Parent', obj.fig_handle, 'Position', [pos_x1, 0.18, w, h], ...
                'Color', [0.12, 0.15, 0.20], 'XColor', [0.6, 0.6, 0.7], 'YColor', [0.6, 0.6, 0.7]);
            obj.line_voltage = plot(obj.ax_voltage, 0, 0, 'Color', [0.95, 0.65, 0.2], 'LineWidth', 2);
            title(obj.ax_voltage, 'Terminal Voltage (V)', 'Color', [0.85, 0.85, 0.85], 'FontSize', 8);
            grid(obj.ax_voltage, 'on');
            
            % Plot 4: Cell Temperature vs Time
            obj.ax_temp = axes('Parent', obj.fig_handle, 'Position', [pos_x2, 0.18, w, h], ...
                'Color', [0.12, 0.15, 0.20], 'XColor', [0.6, 0.6, 0.7], 'YColor', [0.6, 0.6, 0.7]);
            obj.line_temp = plot(obj.ax_temp, 0, 0, 'Color', [1.0, 0.35, 0.35], 'LineWidth', 2);
            title(obj.ax_temp, 'Cell Temperature (°C)', 'Color', [0.85, 0.85, 0.85], 'FontSize', 8);
            grid(obj.ax_temp, 'on');
            
            % Plot 5: Power (Allocated vs Delivered) vs Time
            obj.ax_power = axes('Parent', obj.fig_handle, 'Position', [pos_x1, 0.04, w, h], ...
                'Color', [0.12, 0.15, 0.20], 'XColor', [0.6, 0.6, 0.7], 'YColor', [0.6, 0.6, 0.7]);
            hold(obj.ax_power, 'on');
            obj.line_power_alloc = plot(obj.ax_power, 0, 0, '--m', 'LineWidth', 1.5);
            obj.line_power_deliv = plot(obj.ax_power, 0, 0, 'Color', [0.2, 0.85, 0.9], 'LineWidth', 2);
            title(obj.ax_power, 'Power: Allocated (--) vs Delivered (kW)', 'Color', [0.85, 0.85, 0.85], 'FontSize', 8);
            xlabel(obj.ax_power, 'Sim Time (s)', 'Color', [0.6, 0.6, 0.7], 'FontSize', 8);
            grid(obj.ax_power, 'on');
            
            % Plot 6: Battery Stress Index (BSI) vs Time
            obj.ax_bsi = axes('Parent', obj.fig_handle, 'Position', [pos_x2, 0.04, w, h], ...
                'Color', [0.12, 0.15, 0.20], 'XColor', [0.6, 0.6, 0.7], 'YColor', [0.6, 0.6, 0.7]);
            obj.line_bsi = plot(obj.ax_bsi, 0, 0, 'Color', [1.0, 0.7, 0.1], 'LineWidth', 2);
            title(obj.ax_bsi, 'Battery Stress Index (BSI, 0-100)', 'Color', [0.85, 0.85, 0.85], 'FontSize', 8);
            xlabel(obj.ax_bsi, 'Sim Time (s)', 'Color', [0.6, 0.6, 0.7], 'FontSize', 8);
            grid(obj.ax_bsi, 'on'); ylim(obj.ax_bsi, [0, 100]);
            
            % Load initial vehicle 1 values into GUI fields
            obj.populate_vehicle_fields(1);
        end
        
        function populate_vehicle_fields(obj, veh_id)
            % Populates vehicle configuration fields with selected vehicle's data
            v = obj.user_vehicle_cfg(veh_id);
            set(obj.edit_q_nom,        'String', sprintf('%.1f', v.Q_nom));
            set(obj.edit_init_soc,     'String', sprintf('%.1f', v.initial_SOC * 100));
            set(obj.edit_target_soc,   'String', sprintf('%.1f', v.target_SOC * 100));
            set(obj.edit_init_soh,     'String', sprintf('%.1f', v.initial_SOH * 100));
            set(obj.edit_init_temp,    'String', sprintf('%.1f', v.initial_Temp));
            set(obj.edit_ambient_temp, 'String', sprintf('%.1f', v.T_ambient));
            set(obj.edit_r_initial,    'String', sprintf('%.4f', v.R_initial));
            set(obj.edit_c_max,        'String', sprintf('%.2f', v.C_max));
            set(obj.edit_v_min,        'String', sprintf('%.1f', v.V_min));
            set(obj.edit_v_max,        'String', sprintf('%.1f', v.V_max));
            set(obj.edit_i_max,        'String', sprintf('%.1f', v.I_max));
            set(obj.chk_veh_enabled,   'Value',  logical(v.is_enabled));
        end
        
        function on_vehicle_selection_changed(obj)
            % User chose a different vehicle to inspect or edit in configuration deck
            new_id = get(obj.pop_veh_edit_select, 'Value');
            obj.save_current_vehicle_fields(); % Save previous before switching
            obj.selected_edit_veh_id = new_id;
            obj.populate_vehicle_fields(new_id);
        end
        
        function on_monitor_selection_changed(obj)
            % User chose a different vehicle to view on the live diagnostics & graphs
            obj.monitored_veh_id = get(obj.pop_veh_monitor_select, 'Value');
            % Clear history buffer so graphs show newly selected vehicle cleanly
            obj.history_time        = [];
            obj.history_soc         = [];
            obj.history_target_soc  = [];
            obj.history_curr_deliv  = [];
            obj.history_curr_cmd    = [];
            obj.history_voltage     = [];
            obj.history_temp        = [];
            obj.history_power_alloc = [];
            obj.history_power_deliv = [];
            obj.history_bsi         = [];
        end
        
        function save_current_vehicle_fields(obj)
            % Reads values from GUI textboxes and updates user_vehicle_cfg for selected_edit_veh_id
            vid = obj.selected_edit_veh_id;
            if vid < 1 || vid > length(obj.user_vehicle_cfg); return; end
            
            q_nom     = str2double(get(obj.edit_q_nom, 'String'));
            init_soc  = str2double(get(obj.edit_init_soc, 'String')) / 100.0;
            targ_soc  = str2double(get(obj.edit_target_soc, 'String')) / 100.0;
            init_soh  = str2double(get(obj.edit_init_soh, 'String')) / 100.0;
            init_temp = str2double(get(obj.edit_init_temp, 'String'));
            amb_temp  = str2double(get(obj.edit_ambient_temp, 'String'));
            r_init    = str2double(get(obj.edit_r_initial, 'String'));
            c_max     = str2double(get(obj.edit_c_max, 'String'));
            v_min     = str2double(get(obj.edit_v_min, 'String'));
            v_max     = str2double(get(obj.edit_v_max, 'String'));
            i_max     = str2double(get(obj.edit_i_max, 'String'));
            is_en     = logical(get(obj.chk_veh_enabled, 'Value'));
            
            if ~isnan(q_nom);     obj.user_vehicle_cfg(vid).Q_nom = q_nom; end
            if ~isnan(init_soc);  obj.user_vehicle_cfg(vid).initial_SOC = init_soc; end
            if ~isnan(targ_soc);  obj.user_vehicle_cfg(vid).target_SOC = targ_soc; end
            if ~isnan(init_soh);  obj.user_vehicle_cfg(vid).initial_SOH = init_soh; end
            if ~isnan(init_temp); obj.user_vehicle_cfg(vid).initial_Temp = init_temp; end
            if ~isnan(amb_temp);  obj.user_vehicle_cfg(vid).T_ambient = amb_temp; end
            if ~isnan(r_init);    obj.user_vehicle_cfg(vid).R_initial = r_init; end
            if ~isnan(c_max);     obj.user_vehicle_cfg(vid).C_max = c_max; end
            if ~isnan(v_min);     obj.user_vehicle_cfg(vid).V_min = v_min; end
            if ~isnan(v_max);     obj.user_vehicle_cfg(vid).V_max = v_max; end
            if ~isnan(i_max);     obj.user_vehicle_cfg(vid).I_max = i_max; end
            obj.user_vehicle_cfg(vid).is_enabled = is_en;
        end
        
        function on_input_changed(obj)
            % Triggered whenever any textbox or dropdown changes value
            obj.save_current_vehicle_fields();
            
            % Save station fields
            p_lim = str2double(get(obj.edit_station_power, 'String'));
            if ~isnan(p_lim); obj.user_station_cfg.grid_power_limit = p_lim; end
            
            obj.user_station_cfg.num_vehicles = get(obj.pop_num_vehicles, 'Value');
            
            strat_opts = {'predictive_opt', 'energy_aware', 'equal'};
            obj.user_station_cfg.power_strategy = strat_opts{get(obj.pop_power_strategy, 'Value')};
            
            bms_opts = {'adaptive', 'fixed'};
            obj.user_station_cfg.bms_strategy = bms_opts{get(obj.pop_bms_strategy, 'Value')};
            
            dur = str2double(get(obj.edit_duration, 'String'));
            if ~isnan(dur); obj.user_station_cfg.duration = dur; end
            
            dt = str2double(get(obj.edit_dt, 'String'));
            if ~isnan(dt); obj.user_station_cfg.dt = dt; end
            
            % Execute strict validation
            [is_valid, err_msg] = station_dashboard.validate_config(obj.user_station_cfg, obj.user_vehicle_cfg);
            if is_valid
                set(obj.lbl_validation_status, 'String', 'Status: Configuration Validated & Ready', ...
                    'ForegroundColor', [0.3, 0.9, 0.5]);
            else
                set(obj.lbl_validation_status, 'String', sprintf('Error: %s', err_msg), ...
                    'ForegroundColor', [1.0, 0.3, 0.3]);
            end
        end
        
        function on_action_clicked(obj, action_name)
            % Executes button action callback
            obj.save_current_vehicle_fields();
            [is_valid, err_msg] = station_dashboard.validate_config(obj.user_station_cfg, obj.user_vehicle_cfg);
            if ~is_valid && ~strcmpi(action_name, 'RESET')
                errordlg(sprintf('Cannot proceed with invalid configuration:\n%s', err_msg), 'Configuration Error');
                return;
            end
            
            if ~isempty(obj.action_callback)
                obj.action_callback(action_name, obj.get_user_config());
            end
            
            if strcmpi(action_name, 'TOGGLE_PLAY')
                if strcmpi(obj.sim_state, 'RUNNING')
                    obj.sim_state = 'PAUSED';
                    set(obj.btn_start_pause, 'String', 'RESUME SIMULATION', 'BackgroundColor', [0.2, 0.7, 0.4]);
                else
                    obj.sim_state = 'RUNNING';
                    set(obj.btn_start_pause, 'String', 'PAUSE SIMULATION', 'BackgroundColor', [0.85, 0.5, 0.15]);
                end
            elseif strcmpi(action_name, 'RESET')
                obj.sim_state = 'STOPPED';
                set(obj.btn_start_pause, 'String', 'START SIMULATION', 'BackgroundColor', [0.18, 0.70, 0.35]);
                obj.history_time = [];
                obj.history_soc  = [];
                obj.history_curr_deliv = [];
                obj.history_curr_cmd = [];
                obj.history_voltage = [];
                obj.history_temp = [];
                obj.history_power_alloc = [];
                obj.history_power_deliv = [];
                obj.history_bsi = [];
            end
        end
        
        function cfg_out = get_user_config(obj)
            % Gathers validated station and vehicle configuration structures
            cfg_out.station  = obj.user_station_cfg;
            cfg_out.vehicles = obj.user_vehicle_cfg(1:obj.user_station_cfg.num_vehicles);
        end
        
        function set_action_callback(obj, cb)
            obj.action_callback = cb;
        end
        
        function update_dashboard(obj, sim_time, vehicles, chargers, bays, diag)
            % Real-time dashboard update called directly from simulation loop.
            % Updates station card, vehicle diagnostics, and 6 synchronized graphs.
            
            if obj.is_headless || isempty(obj.fig_handle) || ~isvalid(obj.fig_handle); return; end
            
            %% 1. Station-Level Telemetry
            total_grid_P = sum([chargers.P_grid_kW]);
            total_energy = sum([chargers.energy_delivered_kWh]);
            p_limit      = obj.user_station_cfg.grid_power_limit;
            p_pct        = (total_grid_P / max(p_limit, 0.1)) * 100.0;
            
            avail_bays = sum(strcmpi([bays.status], "AVAILABLE"));
            occ_bays   = sum(strcmpi([bays.status], "OCCUPIED"));
            
            makespan_min = 0.0;
            strat_label  = "Predictive Min-Max";
            if nargin >= 6 && ~isempty(diag)
                if isfield(diag, 'makespan_sec'); makespan_min = diag.makespan_sec / 60.0; end
                if isfield(diag, 'strategy'); strat_label = upper(diag.strategy); end
            end
            
            set(obj.txt_station_grid_load, 'String', ...
                sprintf('Grid Demand: %.2f kW / %.1f kW (%.1f%%)', total_grid_P, p_limit, p_pct));
            set(obj.txt_station_energy, 'String', ...
                sprintf('Total Energy Delivered: %.3f kWh', total_energy));
            set(obj.txt_station_makespan, 'String', ...
                sprintf('Station Completion Makespan: %.1f min', makespan_min));
            set(obj.txt_bay_status, 'String', ...
                sprintf('Bays: %d Available | %d Active', avail_bays, occ_bays));
            
            % Format power allocation breakdown across all bays
            b1 = 0; b2 = 0; b3 = 0; b4 = 0;
            if length(chargers) >= 1; b1 = chargers(1).P_out_kW; end
            if length(chargers) >= 2; b2 = chargers(2).P_out_kW; end
            if length(chargers) >= 3; b3 = chargers(3).P_out_kW; end
            if length(chargers) >= 4; b4 = chargers(4).P_out_kW; end
            
            set(obj.txt_power_breakdown, 'String', ...
                sprintf('Power Distribution: Bay 1: %.2f kW | Bay 2: %.2f kW | Bay 3: %.2f kW | Bay 4: %.2f kW\nActive Strategy: %s | Solver: Bisection Water-Filling', ...
                b1, b2, b3, b4, strat_label));
            
            %% 2. Selected Vehicle Telemetry
            v_idx = find([vehicles.id] == obj.monitored_veh_id, 1);
            if isempty(v_idx) && ~isempty(vehicles)
                v_idx = 1;
                obj.monitored_veh_id = vehicles(1).id;
            end
            
            if ~isempty(v_idx)
                veh = vehicles(v_idx);
                
                is_active = ~isempty(veh.assigned_bay) && veh.assigned_bay > 0;
                bay_str = "En-Route";
                if is_active; bay_str = sprintf("Bay #%d", veh.assigned_bay); end
                
                set(obj.txt_veh_header, 'String', ...
                    sprintf('Vehicle #%d (%s) [%s | %s]', veh.id, veh.type_name, veh.state, bay_str));
                
                init_soc_pct = veh.initial_SOC * 100.0;
                curr_soc_pct = veh.battery.SOC * 100.0;
                targ_soc_pct = veh.battery.target_SOC * 100.0;
                set(obj.txt_veh_soc, 'String', ...
                    sprintf('SOC: Init %.1f%% -> Current %.1f%% (Target %.1f%%)', init_soc_pct, curr_soc_pct, targ_soc_pct));
                
                set(obj.txt_veh_health, 'String', ...
                    sprintf('SOH: %.2f%% | Rint: %.4f Ω | Q_nom: %.1f Ah', ...
                    veh.battery.SOH * 100, veh.battery.Rint, veh.battery.Q_nom));
                
                set(obj.txt_veh_elec, 'String', ...
                    sprintf('Terminal Volt: %.2f V | Current: %.2f A (Cmd: %.2f A)', ...
                    veh.battery.Voltage, veh.battery.Current, veh.I_cmd));
                
                Tamb = obj.cfg.battery.T_ambient;
                if isfield(veh.battery, 'T_ambient'); Tamb = veh.battery.T_ambient; end
                set(obj.txt_veh_thermal, 'String', ...
                    sprintf('Cell Temp: %.2f °C (Amb %.1f °C) | Trip Limit: %.1f °C', ...
                    veh.battery.Temperature, Tamb, obj.cfg.battery.T_trip));
                
                p_alloc = 0.0;
                if isfield(veh, 'P_alloc_kW'); p_alloc = veh.P_alloc_kW; end
                p_deliv = (veh.battery.Voltage * veh.battery.Current) / 1000.0;
                set(obj.txt_veh_power, 'String', ...
                    sprintf('Power: Alloc %.2f kW | Deliv %.2f kW | Injected: %.3f kWh', ...
                    p_alloc, p_deliv, veh.battery.energy_kWh));
                
                bsi_val = veh.BSI;
                bsi_state = "Safe";
                if bsi_val >= obj.cfg.bsi.high_threshold
                    bsi_state = "HIGH STRESS (Derating)";
                elseif bsi_val >= obj.cfg.bsi.warning_threshold
                    bsi_state = "Warning Threshold";
                end
                set(obj.txt_veh_bsi, 'String', ...
                    sprintf('Battery Stress Index (BSI): %.1f / 100 [%s]', bsi_val, bsi_state));
                
                t_rem_min = 0.0;
                if isfield(veh, 'T_pred_sec'); t_rem_min = veh.T_pred_sec / 60.0; end
                
                prot_status = "Normal Operation";
                if veh.battery.is_overtemp; prot_status = "TRIP: Over-Temperature Fault!"; end
                if veh.battery.is_overvoltage; prot_status = "TRIP: Over-Voltage Cutoff!"; end
                if isfield(veh, 'is_enabled') && ~veh.is_enabled; prot_status = "Disabled by User"; end
                
                set(obj.txt_veh_status, 'String', ...
                    sprintf('Mode: %s | C-Rate: %.2f C | Est Time Rem: %.1f min | Status: %s', ...
                    veh.charging_mode, veh.C_rate_cmd, t_rem_min, prot_status));
                
                %% 3. Append to Rolling History & Refresh Plots
                obj.history_time(end+1)        = sim_time;
                obj.history_soc(end+1)         = curr_soc_pct;
                obj.history_target_soc(end+1)  = targ_soc_pct;
                obj.history_curr_deliv(end+1)  = veh.battery.Current;
                obj.history_curr_cmd(end+1)    = veh.I_cmd;
                obj.history_voltage(end+1)     = veh.battery.Voltage;
                obj.history_temp(end+1)        = veh.battery.Temperature;
                obj.history_power_alloc(end+1) = p_alloc;
                obj.history_power_deliv(end+1) = p_deliv;
                obj.history_bsi(end+1)         = bsi_val;
                
                % Limit history buffer to last 400 sample steps
                max_pts = 400;
                if length(obj.history_time) > max_pts
                    obj.history_time        = obj.history_time(end-max_pts:end);
                    obj.history_soc         = obj.history_soc(end-max_pts:end);
                    obj.history_target_soc  = obj.history_target_soc(end-max_pts:end);
                    obj.history_curr_deliv  = obj.history_curr_deliv(end-max_pts:end);
                    obj.history_curr_cmd    = obj.history_curr_cmd(end-max_pts:end);
                    obj.history_voltage     = obj.history_voltage(end-max_pts:end);
                    obj.history_temp        = obj.history_temp(end-max_pts:end);
                    obj.history_power_alloc = obj.history_power_alloc(end-max_pts:end);
                    obj.history_power_deliv = obj.history_power_deliv(end-max_pts:end);
                    obj.history_bsi         = obj.history_bsi(end-max_pts:end);
                end
                
                % Refresh plot lines
                set(obj.line_soc,         'XData', obj.history_time, 'YData', obj.history_soc);
                set(obj.line_target_soc,  'XData', obj.history_time, 'YData', obj.history_target_soc);
                set(obj.line_current,     'XData', obj.history_time, 'YData', obj.history_curr_deliv);
                set(obj.line_i_cmd,       'XData', obj.history_time, 'YData', obj.history_curr_cmd);
                set(obj.line_voltage,     'XData', obj.history_time, 'YData', obj.history_voltage);
                set(obj.line_temp,        'XData', obj.history_time, 'YData', obj.history_temp);
                set(obj.line_power_alloc, 'XData', obj.history_time, 'YData', obj.history_power_alloc);
                set(obj.line_power_deliv, 'XData', obj.history_time, 'YData', obj.history_power_deliv);
                set(obj.line_bsi,         'XData', obj.history_time, 'YData', obj.history_bsi);
                
                t_min = min(obj.history_time);
                t_max = max(obj.history_time) + 1.0;
                if t_max > t_min
                    xlim(obj.ax_soc,     [t_min, t_max]);
                    xlim(obj.ax_current, [t_min, t_max]);
                    xlim(obj.ax_voltage, [t_min, t_max]);
                    xlim(obj.ax_temp,    [t_min, t_max]);
                    xlim(obj.ax_power,   [t_min, t_max]);
                    xlim(obj.ax_bsi,     [t_min, t_max]);
                end
            end
        end
    end
    
    methods (Static)
        function [is_valid, err_msg, val_st, val_v] = validate_config(st_in, v_in)
            % VALIDATE_CONFIG Rigid physical, electrochemical, and dependency validator.
            % Enforces valid ranges, prevents divide-by-zero, negative limits, and broken configs.
            
            is_valid = true;
            err_msg  = "";
            val_st   = st_in;
            val_v    = v_in;
            
            % 1. Station Constraints
            if ~isnumeric(st_in.grid_power_limit) || st_in.grid_power_limit < 2.0 || st_in.grid_power_limit > 100.0
                is_valid = false;
                err_msg = sprintf("Station Power Limit must be in range [2.0, 100.0] kW (Entered: %.2f)", st_in.grid_power_limit);
                return;
            end
            
            if st_in.num_vehicles < 1 || st_in.num_vehicles > 4
                is_valid = false;
                err_msg = sprintf("Number of active vehicles must be between 1 and 4 (Entered: %d)", st_in.num_vehicles);
                return;
            end
            
            if st_in.duration < 10 || st_in.duration > 86400
                is_valid = false;
                err_msg = sprintf("Simulation duration must be in range [10, 86400] seconds (Entered: %.1f)", st_in.duration);
                return;
            end
            
            if st_in.dt < 0.05 || st_in.dt > 5.0
                is_valid = false;
                err_msg = sprintf("Simulation time step dt must be in range [0.05, 5.0] seconds (Entered: %.2f)", st_in.dt);
                return;
            end
            
            % 2. Per-Vehicle Constraints
            N = min(st_in.num_vehicles, length(v_in));
            for i = 1:N
                v = v_in(i);
                prefix = sprintf("Vehicle #%d", v.id);
                
                % Capacity
                if v.Q_nom < 5.0 || v.Q_nom > 250.0
                    is_valid = false;
                    err_msg = sprintf("%s: Capacity Q_nom must be in [5.0, 250.0] Ah (Entered: %.1f)", prefix, v.Q_nom);
                    return;
                end
                
                % SOC
                if v.initial_SOC < 0.01 || v.initial_SOC > 0.99
                    is_valid = false;
                    err_msg = sprintf("%s: Initial SOC must be between 1%% and 99%% (Entered: %.1f%%)", prefix, v.initial_SOC*100);
                    return;
                end
                if v.target_SOC < 0.05 || v.target_SOC > 1.00
                    is_valid = false;
                    err_msg = sprintf("%s: Target SOC must be between 5%% and 100%% (Entered: %.1f%%)", prefix, v.target_SOC*100);
                    return;
                end
                if v.target_SOC <= v.initial_SOC
                    is_valid = false;
                    err_msg = sprintf("%s: Target SOC (%.1f%%) must be strictly greater than Initial SOC (%.1f%%)", ...
                        prefix, v.target_SOC*100, v.initial_SOC*100);
                    return;
                end
                
                % SOH
                if v.initial_SOH < 0.40 || v.initial_SOH > 1.00
                    is_valid = false;
                    err_msg = sprintf("%s: Initial SOH must be in range [40%%, 100%%] (Entered: %.1f%%)", prefix, v.initial_SOH*100);
                    return;
                end
                
                % Temperatures
                if v.initial_Temp < 0.0 || v.initial_Temp > 50.0
                    is_valid = false;
                    err_msg = sprintf("%s: Initial Temperature must be in [0, 50] °C (Entered: %.1f)", prefix, v.initial_Temp);
                    return;
                end
                if v.T_ambient < 0.0 || v.T_ambient > 50.0
                    is_valid = false;
                    err_msg = sprintf("%s: Ambient Temperature must be in [0, 50] °C (Entered: %.1f)", prefix, v.T_ambient);
                    return;
                end
                
                % Resistance
                if v.R_initial < 0.005 || v.R_initial > 0.500
                    is_valid = false;
                    err_msg = sprintf("%s: Initial Resistance must be in [0.005, 0.500] Ω (Entered: %.4f)", prefix, v.R_initial);
                    return;
                end
                
                % C-Rate
                if v.C_max < 0.2 || v.C_max > 3.0
                    is_valid = false;
                    err_msg = sprintf("%s: Max Permitted C-Rate must be in [0.2, 3.0] C (Entered: %.2f)", prefix, v.C_max);
                    return;
                end
                
                % Voltage limits
                if v.V_min < 20.0 || v.V_min > 55.0
                    is_valid = false;
                    err_msg = sprintf("%s: Lower voltage cutoff V_min must be in [20, 55] V (Entered: %.1f)", prefix, v.V_min);
                    return;
                end
                if v.V_max < 35.0 || v.V_max > 70.0
                    is_valid = false;
                    err_msg = sprintf("%s: Upper charging cutoff V_max must be in [35, 70] V (Entered: %.1f)", prefix, v.V_max);
                    return;
                end
                if v.V_max <= v.V_min + 2.0
                    is_valid = false;
                    err_msg = sprintf("%s: V_max (%.1f V) must exceed V_min (%.1f V) by at least 2.0 V", prefix, v.V_max, v.V_min);
                    return;
                end
                
                % Current limit
                if v.I_max < 5.0 || v.I_max > 250.0
                    is_valid = false;
                    err_msg = sprintf("%s: Current Limit I_max must be in [5, 250] A (Entered: %.1f)", prefix, v.I_max);
                    return;
                end
            end
        end
    end
end
