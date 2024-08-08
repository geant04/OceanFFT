// test
#ifndef SKYFUNCTIONS_DEFINE
#define SKYFUNCTIONS_DEFINE

const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;

// Sunset palette
static const float3 sunset[5] =
{
	float3(255, 229, 119) / 255.0,
    float3(254, 192, 81) / 255.0,
    float3(255, 137, 103) / 255.0,
    float3(253, 96, 81) / 255.0,
    float3(57, 32, 51) / 255.0
};
// Dusk palette
static const float3 dusk[5] =
{
	float3(144, 96, 144) / 255.0,
    float3(96, 72, 120) / 255.0,
    float3(72, 48, 120) / 255.0,
    float3(48, 24, 96) / 255.0,
    float3(0, 24, 72) / 255.0
};

const float3 sunColor = float3(255, 255, 190) / 255.0;
const float3 cloudColor = sunset[3];

float2 sphereToUV(float3 p)
{
	float phi = atan2(p.z, p.x);
	if (phi < 0) phi += TWO_PI;
	float theta = acos(p.y);
	return float2(1.0 - phi / TWO_PI, 1.0 - theta / PI);
}

float3 uvToSunset(float2 uv)
{
	if (uv.y < 0.5)
	{
		return sunset[0];
	}
	else if (uv.y < 0.55)
	{
		return lerp(sunset[0], sunset[1], (uv.y - 0.5) / 0.05);
	}
	else if (uv.y < 0.6)
	{
		return lerp(sunset[1], sunset[2], (uv.y - 0.55) / 0.05);
	}
	else if (uv.y < 0.65)
	{
		return lerp(sunset[2], sunset[3], (uv.y - 0.6) / 0.05);
	}
	else if (uv.y < 0.75)
	{
		return lerp(sunset[3], sunset[4], (uv.y - 0.65) / 0.1);
	}
	return sunset[4];
}

float3 uvToDusk(float2 uv)
{
	if (uv.y < 0.5)
	{
		return dusk[0];
	}
	else if (uv.y < 0.55)
	{
		return lerp(dusk[0], dusk[1], (uv.y - 0.5) / 0.05);
	}
	else if (uv.y < 0.6)
	{
		return lerp(dusk[1], dusk[2], (uv.y - 0.55) / 0.05);
	}
	else if (uv.y < 0.65)
	{
		return lerp(dusk[2], dusk[3], (uv.y - 0.6) / 0.05);
	}
	else if (uv.y < 0.75)
	{
		return lerp(dusk[3], dusk[4], (uv.y - 0.65) / 0.1);
	}
	return dusk[4];
}

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
	float3 skyColor;
	float2 uv = sphereToUV(rd);
	//skyColor.xy = uv;
	
	float2 offset = float2(0, 0);
	float3 sunsetColor = uvToSunset(uv + offset * 0.1);
	float3 duskColor = uvToDusk(uv + offset * 0.1);
	
	skyColor = sunsetColor;
	
	// Add a glowing sun in the sky
	float3 sunDir = wi;
	float sunSize = 100;
	float angle = acos(dot(rd, sunDir)) * 360.0 / PI;
    // If the angle between our ray dir and vector to center of sun
    // is less than the threshold, then we're looking at the sun
	if (angle < sunSize)
	{
        // Full center of sun
		if (angle < 7.5)
		{
			skyColor = sunColor;
		}
        // Corona of sun, mix with sky color
		else
		{
			skyColor = lerp(sunColor, sunsetColor, (angle - 7.5) / 22.5);
		}
	}
    // Otherwise our ray is looking into just the sky
	else
	{
		float raySunDot = dot(rd, sunDir);
#define SUNSET_THRESHOLD 0.75
#define DUSK_THRESHOLD -0.1
		if (raySunDot > SUNSET_THRESHOLD)
		{
            // Do nothing, sky is already correct color
		}
        // Any dot product between 0.75 and -0.1 is a LERP b/t sunset and dusk color
		else if (raySunDot > DUSK_THRESHOLD)
		{
			float t = (raySunDot - SUNSET_THRESHOLD) / (DUSK_THRESHOLD - SUNSET_THRESHOLD);
			skyColor = lerp(skyColor, duskColor, t);
		}
        // Any dot product <= -0.1 are pure dusk color
		else
		{
			skyColor = duskColor;
		}
	}
	
	return skyColor;
}

float3 GetSkyColor(float3 rd, float3 wi)
{
	return GetSkyColorOld(rd, wi);
}

float cosGradient (float dcOffset, float amp, float freq, float phase, float x)
{
	float TAU = 6.2831853071795862;
	return clamp((dcOffset + amp * cos(TAU * (phase + freq * x))), 0., 1.);
}

#endif