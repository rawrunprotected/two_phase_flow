
float indexOfRefraction(float levelSetValue)
{
  return levelSetValue < 0 ? refractionIndexPhase0 : refractionIndexPhase1;
}

float3 getAttenuation(float levelSetValue)
{
  float3 att0 = float3(0.05, 1.8, 1.8);
  float3 att1 = float3(1.8, 1.8, 0.05);
  return levelSetValue < 0 ? att0 : att1;
}

float sampleLevelSet(float3 p)
{
  return phi.SampleLevel(clampSampler, p, 0);
}

float3 sampleLevelSetNormal(float3 p)
{
  static const float eps = 1.0 / N;

  float dx = sampleLevelSet(p + float3(eps, 0, 0));
  float dy = sampleLevelSet(p + float3(0, eps, 0));
  float dz = sampleLevelSet(p + float3(0, 0, eps));

  float ex = sampleLevelSet(p - float3(eps, 0, 0));
  float ey = sampleLevelSet(p - float3(0, eps, 0));
  float ez = sampleLevelSet(p - float3(0, 0, eps));

  return normalize(float3(dx, dy, dz) - float3(ex, ey, ez));
}

float3 worldToBoxPos(float3 x)
{
  return x + 0.5;
}

float3 boxToWorldPos(float3 x)
{
  return x - 0.5;
}

float3 worldToBoxDir(float3 x)
{
  return x;
}

float3 boxToWorldDir(float3 x)
{
  return x;
}

void getReflectedAndRefractedRay(float3 normal, float3 dir, float n1, float n2, out float3 Rrefl, out float3 Rfrac, out float Irefl, out float Ifrac)
{
  // Reflected ray direction
  float c1 = dot(normal, dir);
  Rrefl = 2 * c1 * normal - dir;

  // Refraction indices
  const float refq = n1 / n2;

  float rad = 1 - refq * refq * (1 - c1 * c1);

  if (c1 >= 0 && rad >= 0)
  {
    float c2 = sqrt(rad);
    float c3 = refq * c1;
    float c4 = c3 - c2;
    float c5 = refq * c2;
    Rfrac = -refq * dir + c4 * normal;
    float R_s = c4 / (c3 + c2);
    R_s *= R_s;
    float R_p = (c5 - c1) / (c5 + c1);
    R_p *= R_p;

    // Outgoing ray intensities
    Irefl = 0.5 * (R_s + R_p);
    Ifrac = 1 - Irefl;
  }
  else
  {
    Irefl = 1;
    Ifrac = 0;
  }
}

bool intersectBox(float3 rayStartBoxSpace, float3 rayDirBoxSpace, out float2 intersectionDistances)
{
  float3 t1 = (0 - rayStartBoxSpace) / rayDirBoxSpace;
  float3 t2 = (1 - rayStartBoxSpace) / rayDirBoxSpace;

  float3 tmin = min(t1, t2);
  float3 tmax = max(t1, t2);

  float ta = max(tmin.x, max(tmin.y, tmin.z));
  float tb = min(tmax.x, min(tmax.y, tmax.z));

  if (tb >= ta)
  {
    intersectionDistances = float2(ta, tb);
    return true;
  }

  return false;
}

// Finds two points on different sides of the level set surface. By outputting two ray distances
// we can ensure correct continuation of reflection and refraction rays on the respective
// side of the level set.
bool intersectLevelSet(float3 rayStartBoxSpace, float3 rayEndBoxSpace, out float2 intersectionDistances)
{
  float3 rayDir = normalize(rayEndBoxSpace - rayStartBoxSpace);

  float maxDistance = distance(rayEndBoxSpace, rayStartBoxSpace);

  // TODO: Tweak these correctly
  float minStep = 0.1 / N;
  float maxStep = 10.0 / N;
  float stepScale = 0.5;

  // Avoid degenerate tracing
  if (maxDistance <= 1e-6)
  {
    return false;
  }

  float r0 = 0;
  float r1 = minStep;

  float p0 = sampleLevelSet(rayStartBoxSpace + r0 * rayDir);
  float p1 = sampleLevelSet(rayStartBoxSpace + r1 * rayDir);

  for (;;)
  {
    // Found our initial bracket of two points of opposing signs.
    if (p0 * p1 < 0)
    {
      break;
    }

    // Advance stepping
    r0 = r1;
    r1 += clamp(stepScale * abs(p1), minStep, maxStep);

    if (r0 >= maxDistance)
    {
      return false;
    }

    p0 = p1;
    p1 = sampleLevelSet(rayStartBoxSpace + r1 * rayDir);
  }

  // Now both p0 and p1 are != 0, and are of opposite signs.

  // Refine solution via regula falsi.
  for (uint i = 0; i < 10; ++i)
  {
    if (abs(r0 - r1) < 1e-6)
    {
      break;
    }

    float r = (p0 * r1 - p1 * r0) / (p0 - p1);
    float p = sampleLevelSet(rayStartBoxSpace + r * rayDir);

    if (p == 0)
    {
      // We hit an exact zero which we don't want to.
      // Modify one end point to try hitting a different value.
      p0 *= 2;
    }
    else if (sign(p) == sign(p1))
    {
      r1 = r;
      p1 = p;
    }
    else
    {
      r0 = r;
      p0 = p;
    }
  }

  intersectionDistances = float2(r0, r1);

  return true;
}

float3 boxFaceNormal(float3 pointBoxSpace)
{
  pointBoxSpace -= 0.5;

  if (abs(pointBoxSpace.x) > abs(pointBoxSpace.y) && abs(pointBoxSpace.x) > abs(pointBoxSpace.z))
  {
    return float3(sign(pointBoxSpace.x), 0, 0);
  }
  else if (abs(pointBoxSpace.y) > abs(pointBoxSpace.z))
  {
    return float3(0, sign(pointBoxSpace.y), 0);
  }
  else
  {
    return float3(0, 0, sign(pointBoxSpace.z));
  }
}

// Zero-level recursion, don't intersect level set at all.
void traceFluidLevel0(float3 rayStartBoxSpace, float3 rayDirBoxSpace, float3 attenuation)
{
  if (length(rayDirBoxSpace) < 1e-6)
  {
    return;
  }

  // Find end of ray within box
  float2 intersectionDistances;
  if (!intersectBox(rayStartBoxSpace, rayDirBoxSpace, intersectionDistances))
  {
    // Fallback if we didn't find any intersections
    traceHitEnvironment(boxToWorldPos(rayStartBoxSpace), boxToWorldDir(rayDirBoxSpace), attenuation);
    return;
  }

  // Take the 2nd hit which corresponds to the point where the ray exits the box.
  float intersectionDistance = intersectionDistances.y;

  float3 rayEndBoxSpace = rayStartBoxSpace + intersectionDistance * rayDirBoxSpace;

  float levelSetValue = sampleLevelSet(rayStartBoxSpace);

  float3 Rfrac, Rrefl;
  float Ifrac, Irefl;
  getReflectedAndRefractedRay(-boxFaceNormal(rayEndBoxSpace), -normalize(rayDirBoxSpace), indexOfRefraction(levelSetValue), 1.0, Rrefl, Rfrac, Irefl, Ifrac);

  attenuation *= exp(-getAttenuation(levelSetValue) * distance(rayStartBoxSpace, rayEndBoxSpace));

  traceHitEnvironment(boxToWorldPos(rayEndBoxSpace), boxToWorldDir(Rfrac), attenuation * Ifrac);
  traceHitEnvironment(boxToWorldPos(rayEndBoxSpace), boxToWorldDir(Rrefl), attenuation * Irefl);
}

// First level recursion, intersect level set and recurse into base case for each ray.
void traceFluidLevel1(float3 rayStartBoxSpace, float3 rayDirBoxSpace, float3 attenuation)
{
  if (length(rayDirBoxSpace) < 1e-6)
  {
    return;
  }

  float2 intersectionDistances;
  if (!intersectBox(rayStartBoxSpace, rayDirBoxSpace, intersectionDistances))
  {
    // Fallback if we didn't find any intersections
    traceHitEnvironment(boxToWorldPos(rayStartBoxSpace), boxToWorldDir(rayDirBoxSpace), attenuation);
    return;
  }

  // Take the 2nd hit which corresponds to the point where the ray exits the box.
  float intersectionDistance = intersectionDistances.y;

  float3 rayEndBoxSpace = rayStartBoxSpace + intersectionDistance * rayDirBoxSpace;

  float levelSetValueA = sampleLevelSet(rayStartBoxSpace);

  float3 recurseStart;
  float3 recurseDir;
  float3 recurseAttenuation;

  float2 levelSetIntersectionDistances;
  if (!intersectLevelSet(rayStartBoxSpace, rayEndBoxSpace, levelSetIntersectionDistances))
  {
    float3 Rfrac, Rrefl;
    float Ifrac, Irefl;
    getReflectedAndRefractedRay(-boxFaceNormal(rayEndBoxSpace), -normalize(rayDirBoxSpace), indexOfRefraction(levelSetValueA), 1.0, Rrefl, Rfrac, Irefl, Ifrac);

    attenuation *= exp(-getAttenuation(levelSetValueA) * distance(rayStartBoxSpace, rayEndBoxSpace));

    traceHitEnvironment(boxToWorldPos(rayEndBoxSpace), boxToWorldDir(Rfrac), attenuation * Ifrac);

    recurseStart = rayEndBoxSpace;
    recurseDir = Rrefl;
    recurseAttenuation = attenuation * Irefl;
  }
  else
  {
    float3 intersectionPointA = rayStartBoxSpace + normalize(rayEndBoxSpace - rayStartBoxSpace) * levelSetIntersectionDistances.x;
    float3 intersectionPointB = rayStartBoxSpace + normalize(rayEndBoxSpace - rayStartBoxSpace) * levelSetIntersectionDistances.y;

    float levelSetValueB = sampleLevelSet(intersectionPointB);

    float3 intersectionNormal = sign(levelSetValueA) * sampleLevelSetNormal(intersectionPointA);

    float3 Rfrac, Rrefl;
    float Ifrac, Irefl;
    getReflectedAndRefractedRay(intersectionNormal, -normalize(rayDirBoxSpace), indexOfRefraction(levelSetValueA), indexOfRefraction(levelSetValueB), Rrefl, Rfrac, Irefl, Ifrac);

    attenuation *= exp(-getAttenuation(levelSetValueA) * levelSetIntersectionDistances.x);

    traceFluidLevel0(intersectionPointB, Rfrac, attenuation * Ifrac);

    recurseStart = intersectionPointA;
    recurseDir = Rrefl;
    recurseAttenuation = attenuation * Irefl;
  }

  traceFluidLevel0(recurseStart, recurseDir, recurseAttenuation);
}

// Second level recursion, intersect level set and recurse into base case for each ray.
void traceFluidLevel2(float3 rayStartBoxSpace, float3 rayDirBoxSpace, float3 attenuation)
{
  if (length(rayDirBoxSpace) < 1e-6)
  {
    return;
  }

  float2 intersectionDistances;
  if (!intersectBox(rayStartBoxSpace, rayDirBoxSpace, intersectionDistances))
  {
    // Fallback if we didn't find any intersections
    traceHitEnvironment(boxToWorldPos(rayStartBoxSpace), boxToWorldDir(rayDirBoxSpace), attenuation);
    return;
  }

  // Take the 2nd hit which corresponds to the point where the ray exits the box.
  float intersectionDistance = intersectionDistances.y;

  float3 rayEndBoxSpace = rayStartBoxSpace + intersectionDistance * rayDirBoxSpace;

  float levelSetValueA = sampleLevelSet(rayStartBoxSpace);

  float3 recurseStart;
  float3 recurseDir;
  float3 recurseAttenuation;

  float2 levelSetIntersectionDistances;
  if (!intersectLevelSet(rayStartBoxSpace, rayEndBoxSpace, levelSetIntersectionDistances))
  {
    float3 Rfrac, Rrefl;
    float Ifrac, Irefl;
    getReflectedAndRefractedRay(-boxFaceNormal(rayEndBoxSpace), -normalize(rayDirBoxSpace), indexOfRefraction(levelSetValueA), 1.0, Rrefl, Rfrac, Irefl, Ifrac);

    attenuation *= exp(-getAttenuation(levelSetValueA) * distance(rayStartBoxSpace, rayEndBoxSpace));

    traceHitEnvironment(boxToWorldPos(rayEndBoxSpace), boxToWorldDir(Rfrac), attenuation * Ifrac);

    recurseStart = rayEndBoxSpace;
    recurseDir = Rrefl;
    recurseAttenuation = attenuation * Irefl;
  }
  else
  {
    float3 intersectionPointA = rayStartBoxSpace + normalize(rayEndBoxSpace - rayStartBoxSpace) * levelSetIntersectionDistances.x;
    float3 intersectionPointB = rayStartBoxSpace + normalize(rayEndBoxSpace - rayStartBoxSpace) * levelSetIntersectionDistances.y;

    float levelSetValueB = sampleLevelSet(intersectionPointB);

    float3 intersectionNormal = sign(levelSetValueA) * sampleLevelSetNormal(intersectionPointA);

    float3 Rfrac, Rrefl;
    float Ifrac, Irefl;
    getReflectedAndRefractedRay(intersectionNormal, -normalize(rayDirBoxSpace), indexOfRefraction(levelSetValueA), indexOfRefraction(levelSetValueB), Rrefl, Rfrac, Irefl, Ifrac);

    attenuation *= exp(-getAttenuation(levelSetValueA) * levelSetIntersectionDistances.x);

    recurseStart = intersectionPointB;
    recurseDir = Rfrac;
    recurseAttenuation = attenuation * Ifrac;

    // Reflections on the fluid surface are not very important, so go directly to base case instead of tracing the level set a second time.
    traceFluidLevel0(intersectionPointA, Rrefl, attenuation * Irefl);
  }

  traceFluidLevel1(recurseStart, recurseDir, recurseAttenuation);
}

void traceScene(float3 rayStartWorldSpace, float3 rayDirWorldSpace)
{
  float3 rayStartBoxSpace = worldToBoxPos(rayStartWorldSpace);
  float3 rayDirBoxSpace = worldToBoxDir(rayDirWorldSpace);

  float3 color;
  float2 intersectionDistancesBoxSpace;
  if (intersectBox(rayStartBoxSpace, rayDirBoxSpace, intersectionDistancesBoxSpace))
  {
    // Take the first hit, assuming we start outside the box anyway.
    float3 intersectionPointBoxSpace = rayStartBoxSpace + intersectionDistancesBoxSpace.x * rayDirBoxSpace;

    float3 Rfrac, Rrefl;
    float Ifrac, Irefl;
    getReflectedAndRefractedRay(boxFaceNormal(intersectionPointBoxSpace), normalize(rayStartBoxSpace - intersectionPointBoxSpace), 1.0, indexOfRefraction(sampleLevelSet(intersectionPointBoxSpace)), Rrefl, Rfrac, Irefl, Ifrac);

    traceHitEnvironment(boxToWorldPos(intersectionPointBoxSpace), boxToWorldDir(Rrefl), Irefl.xxx);
    traceFluidLevel2(intersectionPointBoxSpace, Rfrac, Ifrac.xxx);
  }
  else
  {
    // If we don't hit the box, go directly to environment.
    traceHitEnvironment(rayStartWorldSpace, rayDirWorldSpace, 1.0.xxx);
  }
}