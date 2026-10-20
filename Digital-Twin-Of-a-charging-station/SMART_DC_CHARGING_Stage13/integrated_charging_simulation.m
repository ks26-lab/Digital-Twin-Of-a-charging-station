function result = integrated_charging_simulation(duration_s, dt_s)
%INTEGRATED_CHARGING_SIMULATION Run stateless step loop and return 9 signals.
if nargin<1, duration_s=3600; end
if nargin<2, dt_s=1; end
p=parameters();
n=floor(duration_s/dt_s)+1; t=(0:n-1)'*dt_s;
y=zeros(n,9); x=[0.20; p.Tamb_C; 0; 1];
for k=1:n
    [y(k,:),x]=smart_battery_step(x,dt_s,p,1);
end
result=array2table([t y],'VariableNames',{'time_s','Voltage','Current','SOC','Temperature','Rint','BSI','TargetC_rate','ChargeMode','SafetyStatus'});
end
