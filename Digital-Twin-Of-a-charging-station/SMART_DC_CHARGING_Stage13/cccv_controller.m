function [current_A, mode] = cccv_controller(soc, voltage_V, requested_C, p)
%CCCV_CONTROLLER Basic CC/CV charging current request. 0=off,1=CC,2=CV.
if soc >= p.SOCmax || voltage_V >= p.Vmax_V || requested_C <= 0
    current_A = 0; mode = 0;
elseif voltage_V < p.Vmax_V-0.10 && soc < 0.80
    current_A = requested_C*p.Q_Ah; mode = 1;
else
    headroom = max(p.Vmax_V-voltage_V,0);
    current_A = min(requested_C*p.Q_Ah, max(p.CV_taper_A, p.Imax_A*headroom/0.10));
    mode = 2;
end
current_A = min(max(current_A,0),p.Imax_A);
end
