function c = adaptive_crate(soc, T_C, soh, p)
%ADAPTIVE_CRATE Heuristic charge-rate request in C-rate units.
c = p.CC_C_rate;
if soc >= 0.80, c = min(c,0.30); end
if T_C >= p.Twarn_C-5, c = min(c,0.20); end
if soh < 0.80, c = min(c,0.25); end
if soc >= p.SOCmax-0.01 || T_C >= p.Tstop_C, c = 0; end
end
