function run_basic_checks()
%RUN_BASIC_CHECKS Simple consistency checks; called by main.
p=parameters();
assert(p.Q_Ah>0 && p.Imax_A>0 && p.dt_s>0,'Parameters must be positive.');
v=battery_voltage(0.5,1,p); assert(v>3 && v<4.2,'Voltage sanity check failed.');
assert(abs(soc_estimator(0.5,1,3600,p)-(0.5+1/p.Q_Ah))<1e-12,'SOC check failed.');
x=[0.2;25;0;1]; [y,x2]=smart_battery_step(x,1,p,1);
assert(numel(y)==9 && numel(x2)==4,'Integrated signal/state dimensions are wrong.');
assert(all(isfinite(y)) && all(isfinite(x2)),'Step output contains non-finite values.');
end
