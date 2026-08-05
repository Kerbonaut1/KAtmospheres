# K Atmospheres
> Kerbonaut's Atmospheres

<img src="Imgs/Screenshot 2026-08-05 230626.png" alt="Alt Text" width="1000">
<img src="Imgs/Screenshot 2026-08-05 230615.png" alt="Alt Text" width="1000">

## Constraints:
None lol put as many as u want in a level

## Atmosphere Parameters
### Planet Info
- float planet_radius = 100.0;
- float atmosphere_radius = 120.0;
### Scattering Parameters
- vec3 rayleigh_coefficients = vec3(0.0058, 0.0135, 0.0331); 
- float rayleigh_scale_height = 8.0; 
- float mie_coefficient = 0.021;
- float mie_scale_height = 1.2;
- float mie_g = 0.76; 
- float sun_intensity = 10.0;
- float multi_scatter_strength : hint_range(0.0, 1.0) = 0.4;
- int multi_scatter_octaves : hint_range(1, 6) = 4;
- float multi_scatter_falloff : hint_range(0.0, 1.0) = 0.5;
### Quality
- int view_steps : hint_range(4, 64) = 16;
- int light_steps : hint_range(2, 32) = 8;


