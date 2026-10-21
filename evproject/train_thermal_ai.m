% --- PHASE 15 & 17: PREDICTIVE AI FOR THERMAL & BSI FORECASTING ---

% 1. Load the generated thermal dataset
data = readtable('Predictive_Thermal_Dataset.csv');

% 2. Feature Engineering
% We build a matrix of the battery's CURRENT state (SOH, Resistance, Age)
X_features = [ones(height(data), 1), data.SOH, data.Resistance, log10(data.Cycle)];

% The TARGETS we want the AI to predict (FUTURE heat and stress)
Y_Temp = data.Max_Temp;
Y_BSI = data.Max_BSI;

% 3. Time-Series Train/Test Split (70/30)
split_idx = round(0.7 * height(data));

X_train = X_features(1:split_idx, :);
X_test = X_features(split_idx+1:end, :);

Y_Temp_train = Y_Temp(1:split_idx);
Y_Temp_test = Y_Temp(split_idx+1:end);

Y_BSI_train = Y_BSI(1:split_idx);
Y_BSI_test = Y_BSI(split_idx+1:end);

% 4. Train Native ML Models (Normal Equation)
fprintf('Training Predictive Thermal & BSI AI Models...\n');
weights_Temp = X_train \ Y_Temp_train;
weights_BSI = X_train \ Y_BSI_train;

% 5. Predictions & Validation (On Unseen Future Data)
pred_Temp = X_test * weights_Temp;
pred_BSI = X_test * weights_BSI;

% Calculate RMSE to prove accuracy
RMSE_Temp = sqrt(mean((Y_Temp_test - pred_Temp).^2));
RMSE_BSI = sqrt(mean((Y_BSI_test - pred_BSI).^2));

fprintf('Thermal Prediction Error (RMSE): %.6f °C\n', RMSE_Temp);
fprintf('BSI Prediction Error (RMSE): %.6f\n', RMSE_BSI);

% 6. Visualization
figure('Name', 'Predictive Thermal & BSI AI', 'Color', 'w', 'Position', [100, 100, 1000, 450]);

% Subplot 1: Phase 15 (Thermal Prediction)
subplot(1,2,1);
plot(data.Cycle(split_idx+1:end), Y_Temp_test, 'o', 'MarkerEdgeColor', 'b', 'MarkerFaceColor', 'b', 'DisplayName', 'True Peak Temp');
hold on;
plot(data.Cycle(split_idx+1:end), pred_Temp, '-', 'Color', 'r', 'LineWidth', 2, 'DisplayName', 'AI Predicted Temp');
title('Phase 15: Thermal Forecast (Future 30%)');
xlabel('Total Charge Cycles'); ylabel('Peak Temperature (°C)');
legend('Location', 'best'); grid on; set(gca, 'FontSize', 10);

% Subplot 2: Phase 17 (BSI Prediction)
subplot(1,2,2);
plot(data.Cycle(split_idx+1:end), Y_BSI_test, 'o', 'MarkerEdgeColor', 'g', 'MarkerFaceColor', 'g', 'DisplayName', 'True Peak BSI');
hold on;
plot(data.Cycle(split_idx+1:end), pred_BSI, '-', 'Color', 'r', 'LineWidth', 2, 'DisplayName', 'AI Predicted BSI');
title('Phase 17: Battery Stress Forecast');
xlabel('Total Charge Cycles'); ylabel('Peak BSI Score');
legend('Location', 'best'); grid on; set(gca, 'FontSize', 10);