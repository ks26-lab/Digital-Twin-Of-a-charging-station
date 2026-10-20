function [y, xNext] = smart_battery_step(x, dt_s, p, sohInput)
%SMART_BATTERY_STEP Stateless one-step simulation.
% x=[SOC; temperature_C; previous_current_A; SOH]. y follows the nine-output
% order: V, I, SOC, temperature_C, Rint_Ohm, BSI, C-rate, chargeMode, safety.
soc=min(max(x(1),0),1); T=x(2); soh=min(max(sohInput,0),1);
if nargin<4, soh=min(max(x(4),0),1); end
r=p.Rint_Ohm;
v=battery_voltage(soc,0,p);
crate=adaptive_crate(soc,T,soh,p);
[i,mode]=cccv_controller(soc,v,crate,p);
status=safety_status(T,soc,v,p);
[v,~]=battery_model(soc,i,p);
status=safety_status(T,soc,v,p);
if status==2 || (status==1 && T>=p.Tstop_C-2)
    i=0; mode=0; v=battery_voltage(soc,0,p);
end
socNext=soc_estimator(soc,i,dt_s,p);
Tnext=thermal_model(T,i,dt_s,p);
ocv=3.0+1.2*soc;
r=rint_estimator(v,ocv,i,p.Rint_Ohm);
bsi=bsi_estimator(T,soc,r,p);
y=[v;i;soc;T;r;bsi;crate;mode;status];
xNext=[socNext;Tnext;i;soh];
end
