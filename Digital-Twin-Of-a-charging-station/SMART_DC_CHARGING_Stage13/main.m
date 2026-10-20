function main()
%MAIN Run basic checks, simulate one synthetic charging session, plot outputs.
run_basic_checks();
syntheticProfile=generate_synthetic_data(1800,1); %#ok<NASGU>
result=integrated_charging_simulation(3600,1);
disp(result(1:min(10,height(result)),:));
figure('Name','SMART DC Charging — teaching simulation');
names=result.Properties.VariableNames(2:end);
for k=1:9
    subplot(9,1,k); plot(result.time_s,result{:,k+1}); grid on; ylabel(names{k},'Interpreter','none');
end
xlabel('Time (s)');
end
