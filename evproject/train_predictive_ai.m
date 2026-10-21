% --- PHASE 12 & 13: NATIVE ML FEATURE ENGINEERING & SOH PREDICTION ---

% 1. Load the generated dataset from Phase 11
data = readtable('Battery_Aging_ML_Dataset.csv');

% ==========================================
% 2. PHASE 12: FEATURE ENGINEERING
% ==========================================
data.Delta_Resistance = data.Resistance_Ohms - 0.050;
data.R_Smoothed = movmean(data.Resistance_Ohms, 5);
data.Log_Cycle = log10(data.Cycle);

% ==========================================
% 3. TIME-SERIES TRAIN / TEST SPLIT
% ==========================================
% Train on the first 70% of life, predict the final 30% of life natively
split_idx = round(0.7 * height(data));
trainData = data(1:split_idx, :);
testData = data(split_idx+1:end, :);

% ==========================================
% 4. PHASE 13: NATIVE AI MODEL TRAINING
% ==========================================
fprintf('Training Native ML Regression Model...\n');

% Build the Feature Matrix (X) and Target Vector (Y) for Training
% We add a column of ones for the mathematical 'bias' or 'intercept'
X_train = [ones(height(trainData), 1), trainData.Log_Cycle, trainData.Delta_Resistance, trainData.R_Smoothed];
Y_train = trainData.SOH;

% Train the Model using the Normal Equation (Base MATLAB Matrix Math)
% This calculates the perfect weights for the AI without any toolboxes!
weights = X_train \ Y_train; 

% ==========================================
% 5. PREDICTION & VALIDATION (ON FUTURE DATA)
% ==========================================
% Format the unseen test data exactly like the training data
X_test = [ones(height(testData), 1), testData.Log_Cycle, testData.Delta_Resistance, testData.R_Smoothed];

% Ask the AI to predict the SOH for the unseen future
predicted_SOH = X_test * weights;
actual_SOH = testData.SOH;

% Calculate the Root Mean Square Error (RMSE)
RMSE = sqrt(mean((actual_SOH - predicted_SOH).^2));
fprintf('AI Prediction Error (RMSE): %.6f\n', RMSE);

% ==========================================
% 6. VISUALIZATION
% ==========================================
figure('Name', 'Native ML State of Health Prediction', 'Color', 'w', 'Position', [150, 150, 900, 450]);
plot(testData.Cycle, actual_SOH * 100, 'o', 'MarkerEdgeColor', 'b', 'MarkerFaceColor', 'b', 'DisplayName', 'Actual Physical SOH');
hold on;
plot(testData.Cycle, predicted_SOH * 100, '-', 'Color', 'r', 'LineWidth', 2, 'DisplayName', 'AI Predicted SOH');
title('Machine Learning Prediction vs Actual Battery Degradation (Future 30%)');
xlabel('Total Charge Cycles'); ylabel('State of Health (%)');
legend('Location', 'best'); grid on; set(gca, 'FontSize', 11);

% ==========================================
% 7. PHASE 14 & 16: CAPACITY & EOL PREDICTION
% ==========================================
fprintf('\nExecuting Phase 14 & 16: Capacity Fade Prediction...\n');

% 1. Convert predicted SOH directly to predicted Capacity
Nominal_Capacity = 50; % Ah
Predicted_Capacity = predicted_SOH * Nominal_Capacity;
Actual_Capacity = testData.Capacity_Ah;

% 2. Identify the exact End-of-Life (EOL) point
% The industry standard for EV battery EOL is 80% SOH, which is 40 Ah.
% We ask the AI to identify exactly which cycle crossed this threshold.
EOL_Threshold = 40.0;
death_index = find(Predicted_Capacity <= EOL_Threshold, 1);
EOL_Cycle = testData.Cycle(death_index);

fprintf('AI PREDICTION: Battery End of Life (40 Ah) occurs at Cycle %d\n', EOL_Cycle);

% 3. Visualization
figure('Name', 'Phase 14: AI Capacity Prediction', 'Color', 'w', 'Position', [200, 200, 900, 450]);
plot(testData.Cycle, Actual_Capacity, 'o', 'MarkerEdgeColor', 'b', 'MarkerFaceColor', 'b', 'DisplayName', 'True Capacity (Simulink)');
hold on;
plot(testData.Cycle, Predicted_Capacity, '-', 'Color', 'r', 'LineWidth', 2, 'DisplayName', 'AI Predicted Capacity');

% Add the EOL target line
yline(EOL_Threshold, '--k', 'End of Life Threshold (40 Ah)', 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');

% Mark the exact death cycle
plot(EOL_Cycle, EOL_Threshold, 'p', 'MarkerSize', 15, 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k', 'DisplayName', 'Predicted Failure Point');

title('Machine Learning Capacity Fade & Remaining Useful Life (RUL)');
xlabel('Total Charge Cycles'); ylabel('Usable Capacity (Ah)');
legend('Location', 'best'); grid on; set(gca, 'FontSize', 11);