function data = generate_synthetic_data(duration_s, dt_s)
%GENERATE_SYNTHETIC_DATA Deterministic toy profile; not measured or validated.
if nargin<1, duration_s=1800; end
if nargin<2, dt_s=1; end
t=(0:dt_s:duration_s)';
ambient=25+2*sin(2*pi*t/max(duration_s,1));
loadCurrent=0.2+0.1*sin(2*pi*t/300); % illustrative synthetic load
data=table(t,ambient,loadCurrent,'VariableNames',{'time_s','ambient_C','synthetic_load_A'});
end
