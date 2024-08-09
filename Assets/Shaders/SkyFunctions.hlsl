// test
#ifndef SKYFUNCTIONS_DEFINE
#define SKYFUNCTIONS_DEFINE

const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;

float3 GetSkyColorOld(float3 rd, float3 wi)
{
	float sun_amount = max(dot(rd, wi), 0.0);
	float3 sun_color = float3(1., .7, .55);

	float3 sky = lerp(float3(.0, .1, .4), float3(.3, .6, .8), 1.0 - rd.y);
	sky = sky + sun_color * min(pow(sun_amount, 1000.0) * 0.1, 1.0);
	sky = sky + sun_color * min(pow(sun_amount, 2.0) * .6, 1.0);

	return sky;
}

float3 GetSkyColorNew(float3 rd, float3 wi)
{
	float dy = rd.y * 0.50 + 0.50;
	
	float sun_amount = max(dot(rd, wi), 0.0);
	float3 dayColor1 = float3(255.0, 255.0, 255.0) / 255.0;
	float3 dayColor2 = float3(150.0, 209.0, 255.0) / 255.0;
	
	float3 sky = lerp(dayColor1, dayColor2, clamp(dy, 0, 1));
	
	float3 sun_color = float3(1., 1., .55);
	sky = sky + sun_color * min(pow(sun_amount, 1000.0), 1.0);
	
	return sky;
}

float3 GetSkyColor(float3 rd, float3 wi)
{
	return GetSkyColorNew(rd, wi);
}

float2 sphereToUV(float3 p)
{
	float phi = atan2(p.z, p.x);
	if (phi < 0)
		phi += TWO_PI;
	float theta = acos(p.y);
	return float2(1.0 - phi / TWO_PI, 1.0 - theta / PI);
}

float3 GetSkyColorFromOcean(float3 rd, float3 wi)
{
	
	return GetSkyColorNew(rd * float3(1.0, 0.1, 1.0), wi);
}

#endif