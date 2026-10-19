function status = safety_status(T_C, soc, voltage_V, p)
%SAFETY_STATUS 0 normal, 1 warning, 2 stop. Illustrative thresholds only.
if T_C >= p.Tstop_C || soc >= p.SOCmax || voltage_V >= p.Vmax_V+0.05
    status = 2;
elseif T_C >= p.Twarn_C || soc >= p.SOCmax-0.03 || voltage_V >= p.Vmax_V-0.05
    status = 1;
else
    status = 0;
end
end
