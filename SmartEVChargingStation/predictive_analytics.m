classdef predictive_analytics
    % PREDICTIVE_ANALYTICS Self-contained predictive battery health and thermal
    % stress forecasting engine.
    %
    % Addresses Section 6 Requirements:
    %   1. Explicit function/object loading (NO accidental base-workspace variables)
    %   2. Clean, reproducible training and inference
    %   3. Explicit documentation of model provenance and validation metrics (RMSE)
    %   4. Transparent disclosure of synthetic dataset origin (no false AI claims)
    %   5. Safe physics-informed baseline fallback when model is absent or invalid
    %   6. Closed-loop proactive C-rate throttling advisory for BMS controller
    
    methods (Static)
        function model = get_model(custom_csv_path)
            % GET_MODEL Loads or trains the predictive model from dataset.
            % Searches in priority order: custom path, evproject, or current dir.
            
            model.is_trained = false;
            model.weights_Temp = [];
            model.weights_BSI  = [];
            model.rmse_temp    = NaN;
            model.rmse_bsi     = NaN;
            model.features     = ["Intercept", "SOH", "Rint", "log10(Cycle)"];
            model.provenance   = "Uninitialized";
            model.note         = "";
            
            % Locate CSV dataset
            csv_path = "";
            if nargin >= 1 && ~isempty(custom_csv_path) && exist(custom_csv_path, 'file')
                csv_path = custom_csv_path;
            else
                candidate_paths = {
                    fullfile(fileparts(mfilename('fullpath')), 'Predictive_Thermal_Dataset.csv'), ...
                    fullfile(fileparts(mfilename('fullpath')), '..', 'evproject', 'Predictive_Thermal_Dataset.csv'), ...
                    'Predictive_Thermal_Dataset.csv'
                };
                for i = 1:length(candidate_paths)
                    if exist(candidate_paths{i}, 'file')
                        csv_path = candidate_paths{i};
                        break;
                    end
                end
            end
            
            if isempty(csv_path) || ~exist(csv_path, 'file')
                model.is_trained = false;
                model.provenance = "Physics-Informed Baseline Estimator (Dataset not found)";
                model.note = "Clean physics baseline active. No base-workspace dependencies.";
                return;
            end
            
            try
                % Read dataset
                data = readtable(csv_path);
                required_cols = {'SOH', 'Resistance', 'Cycle', 'Max_Temp', 'Max_BSI'};
                for c = 1:length(required_cols)
                    if ~ismember(required_cols{c}, data.Properties.VariableNames)
                        error('Missing column in dataset: %s', required_cols{c});
                    end
                end
                
                N = height(data);
                if N < 10
                    error('Dataset has insufficient rows (%d < 10)', N);
                end
                
                % Features: [1, SOH, Rint, log10(Cycle)]
                X = [ones(N, 1), data.SOH, data.Resistance, log10(max(data.Cycle, 1))];
                Y_Temp = data.Max_Temp;
                Y_BSI  = data.Max_BSI;
                
                % 70/30 Train/Test Split (Temporal order preserved)
                split_idx = round(0.70 * N);
                X_train = X(1:split_idx, :);
                X_test  = X(split_idx+1:end, :);
                
                Y_T_train = Y_Temp(1:split_idx);
                Y_T_test  = Y_Temp(split_idx+1:end);
                
                Y_B_train = Y_BSI(1:split_idx);
                Y_B_test  = Y_BSI(split_idx+1:end);
                
                % Solve via regularized OLS / Normal Equation
                lambda = 1e-4; % Ridge regularization for numerical stability
                I_reg = eye(size(X, 2)); I_reg(1,1) = 0;
                weights_Temp = (X_train' * X_train + lambda * I_reg) \ (X_train' * Y_T_train);
                weights_BSI  = (X_train' * X_train + lambda * I_reg) \ (X_train' * Y_B_train);
                
                % Evaluate generalization error on unseen test split
                pred_T_test = X_test * weights_Temp;
                pred_B_test = X_test * weights_BSI;
                
                rmse_temp = sqrt(mean((Y_T_test - pred_T_test).^2));
                rmse_bsi  = sqrt(mean((Y_B_test - pred_B_test).^2));
                
                % Populate validated model struct
                model.is_trained   = true;
                model.weights_Temp = weights_Temp;
                model.weights_BSI  = weights_BSI;
                model.rmse_temp    = rmse_temp;
                model.rmse_bsi     = rmse_bsi;
                model.dataset_path = csv_path;
                model.provenance   = sprintf("Trained on %s via Regularized OLS", csv_path);
                model.note         = "Synthetic dataset generated via multi-cycle polynomial thermal model. Labels reflect simulated degradation.";
                
            catch ME
                model.is_trained = false;
                model.provenance = sprintf("Baseline Fallback (Training failed: %s)", ME.message);
                model.note       = "Fell back to physics-informed baseline.";
            end
        end
        
        function [pred_peak_T, pred_peak_BSI, C_max_advice, info] = forecast(model, battery_state, cycle_count, cfg)
            % FORECAST Evaluates predictive stress forecast for upcoming charging session.
            %
            % Inputs:
            %   model         - Validated model struct from get_model()
            %   battery_state - Current battery state struct (SOH, Rint, T_ambient, C_max, Q_nom)
            %   cycle_count   - Cumulative battery cycle count (scalar)
            %   cfg           - System configuration struct
            %
            % Outputs:
            %   pred_peak_T   - Forecasted peak cell temperature [deg C]
            %   pred_peak_BSI - Forecasted peak Battery Stress Index [0-100]
            %   C_max_advice  - Recommended safe C-rate ceiling [h^-1]
            %   info          - Diagnostic metadata struct (provenance, method, errors)
            
            if nargin < 3 || isempty(cycle_count); cycle_count = 100; end
            
            SOH   = battery_state.SOH;
            Rint  = battery_state.Rint;
            C_max = battery_state.C_max;
            Q_nom = battery_state.Q_nom;
            
            Tamb = cfg.battery.T_ambient;
            if isfield(battery_state, 'T_ambient') && ~isempty(battery_state.T_ambient)
                Tamb = battery_state.T_ambient;
            end
            
            if isfield(model, 'is_trained') && model.is_trained && ~isempty(model.weights_Temp)
                % Method 1: Trained Machine Learning Model
                X = [1.0, SOH, Rint, log10(max(cycle_count, 1.0))];
                pred_peak_T   = X * model.weights_Temp;
                pred_peak_BSI = X * model.weights_BSI;
                
                % Bound predictions to physical limits
                pred_peak_T   = min(max(pred_peak_T, Tamb), 60.0);
                pred_peak_BSI = min(max(pred_peak_BSI, 0.0), 100.0);
                
                info.method     = "Trained ML Model (OLS)";
                info.provenance = model.provenance;
                info.rmse_temp  = model.rmse_temp;
                info.rmse_bsi   = model.rmse_bsi;
                info.note       = model.note;
            else
                % Method 2: Physics-Informed Baseline Estimator
                % Peak thermal equilibrium under full design current:
                % P_loss = I^2 * Rint
                % dT_max = P_loss / h_thermal
                I_peak = min(C_max * Q_nom, cfg.charger.I_max);
                P_loss = (I_peak ^ 2) * Rint;
                dT_max = P_loss / max(cfg.battery.h_thermal, 1.0);
                pred_peak_T = Tamb + dT_max;
                
                % Approximate BSI at peak stress condition
                stress_C   = min((I_peak / max(Q_nom, 1.0)) / max(C_max, 0.1), 1.0);
                stress_T   = min(max((pred_peak_T - Tamb) / (cfg.battery.T_trip - Tamb), 0.0), 1.0);
                stress_SOC = 0.85; % Assume stress at 90% SOC
                stress_R   = min(max((Rint / battery_state.R_initial - 1.0) / 0.50, 0.0), 1.0);
                stress_SOH = min(max((1.0 - SOH) / 0.30, 0.0), 1.0);
                
                pred_peak_BSI = 100.0 * (cfg.bsi.wC   * stress_C + ...
                                         cfg.bsi.wT   * stress_T + ...
                                         cfg.bsi.wSOC * stress_SOC + ...
                                         cfg.bsi.wR   * stress_R + ...
                                         cfg.bsi.wSOH * stress_SOH);
                pred_peak_BSI = min(max(pred_peak_BSI, 0.0), 100.0);
                
                info.method     = "Physics-Informed Baseline Estimator";
                info.provenance = "Analytical lumped-parameter thermal equilibrium";
                info.rmse_temp  = NaN;
                info.rmse_bsi   = NaN;
                info.note       = "Used because no trained model was provided or dataset was absent.";
            end
            
            % Proactive C-Rate Throttling Decision Matrix
            % Proactively throttles charger before stress causes damage
            if pred_peak_BSI >= 54.0 || pred_peak_T >= 38.0
                C_max_advice = min(C_max, 0.90); % Aggressive throttling for aged/stressed packs
                info.decision = "Aggressive Derate (Old/High-Stress Pack)";
            elseif pred_peak_BSI >= 52.0 || pred_peak_T >= 34.0
                C_max_advice = min(C_max, 1.20); % Moderate throttling
                info.decision = "Moderate Derate (Elevated Stress Predicted)";
            else
                C_max_advice = C_max;            % Full speed authorized
                info.decision = "Full Speed Authorized (Healthy Pack)";
            end
            
            info.pred_peak_T   = pred_peak_T;
            info.pred_peak_BSI = pred_peak_BSI;
            info.C_max_advice  = C_max_advice;
        end
    end
end
