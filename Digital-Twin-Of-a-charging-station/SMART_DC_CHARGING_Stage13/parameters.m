function p = parameters()
%PARAMETERS Illustrative single-cell parameters; not a real cell datasheet.
p.Q_Ah = 2.5;
p.Vmin_V = 3.0;
p.Vmax_V = 4.2;
p.Imax_A = 2.5;
p.Rint_Ohm = 0.08;
p.Rth_K_per_W = 3.0;
p.Cth_J_per_K = 500;
p.Tamb_C = 25;
p.Twarn_C = 45;
p.Tstop_C = 55;
p.SOCmin = 0.02;
p.SOCmax = 0.98;
p.CC_C_rate = 0.5;
p.CV_taper_A = 0.125;
p.dt_s = 1;
end
