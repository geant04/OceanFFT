using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class OceanScript : MonoBehaviour
{
    List<GameObject> ActiveTiles;
    GameObject Tile;
    int tiles = 0;

    // Assign a camera to begin?
    public Camera MainCamera;

    Mesh Mesh;
    Material OceanMaterial;

    // Shaders + Compute Shader params
    public ComputeShader OceanComputeShader;
    private int threadGroupsX, threadGroupsY;

    public Shader OceanShader;

    // Sky
    public Material SkyMaterial;

    // SerializeFields
    [SerializeField] Vector2 Size = new Vector2(1, 1);
    [SerializeField] int planeResolution = 1;
    [SerializeField] int N = 512;
    [SerializeField] int[] L = { 64, 32 };
    [SerializeField] float[] intensity = { 8, 32 };
    [SerializeField] float[] windSpeed = { 5000, 16};
    [SerializeField] float[] waveSize = { 4000, 2000 };
    [SerializeField][Range(0.0f, 10.0f)] float[] Scales = { 1, 1 };
    [SerializeField] [Range(0.0f, 10.0f)] float t0;
    [SerializeField] [Range(0.0f, 10.0f)] float t1;
    [SerializeField] Vector2 windDirection;
    [Range(0.0f, 1.0f)] public float timeOfDay;

    // RenderTextures
    private RenderTexture heightMap,
                          normalMap,
                          initialSpectrum,
                          spectrumTexture,
                          FFTBuffer;

    private RenderTexture[] heightMaps;
    private RenderTexture[] spectrumTextures;
    private RenderTexture[] initialSpectrums;
    
    // Misc.
    Vector3[] vertices;
    private int prevN;
    private int cascades;
    private int[] prevL = { 0, 0 };
    private float[] prevIntensity = { 0, 0 };
    private float[] prevWindSpeed = { 0, 0 };
    private float[] prevWaveSize = { 0, 0 };
    private float prevTimeOfDay;

    // Tiling camera stuff
    private Vector3 previousCameraPosition;
    private Quaternion previousCameraRotation;
    private Dictionary<Vector3, GameObject> existingTiles = new Dictionary<Vector3, GameObject>();

    // Builds nxm sized grid with i resolution
    void CreatePlane()
    {
        Mesh = new Mesh();
        Mesh.name = "Ocean Mesh";
        Mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        vertices = new Vector3[(planeResolution + 1) * (planeResolution + 1)];
        float xPerStep = Size.x / planeResolution;
        float zPerStep = Size.y / planeResolution;


        Vector2[] uvs = new Vector2[vertices.Length];
        Vector4[] tangents = new Vector4[vertices.Length];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);

        // this is a neat i = 0 trick to get the index
        for (int i = 0, z = 0; z < planeResolution + 1; z++) {
            for (int x = 0; x < planeResolution + 1; x++, i++) {
                vertices[i] = new Vector3(((float)x * xPerStep) - (Size.y / 2) , 0, ((float)z * zPerStep) - (Size.y / 2));
                uvs[i] = new Vector2((float)x / planeResolution, (float)z / planeResolution);
                tangents[i] = tangent;
            }
        }

        Mesh.vertices = vertices;
        Mesh.uv = uvs;
        Mesh.tangents = tangents;

        int[] triangles = new int[planeResolution * planeResolution * 6];
        
        for (int row = 0; row < planeResolution; row++) {
            for (int column = 0; column < planeResolution; column++) {
                int i = (row * (planeResolution + 1) + column);
                int idx = (row * planeResolution + column) * 6;

                triangles[idx] = i;
                triangles[idx + 1] = i + planeResolution + 1;
                triangles[idx + 2] = i + planeResolution + 2;

                triangles[idx + 3] = i;
                triangles[idx + 4] = i + planeResolution + 2;
                triangles[idx + 5] = i + 1;
            }
        }

        Mesh.triangles = triangles;
    }
    void CreateMaterial()
    {
        OceanMaterial = new Material(OceanShader);
        OceanMaterial.name = "Ocean Material";
        //GetComponent<MeshRenderer>().material = OceanMaterial;
    }

    GameObject CreateTile(Vector3 tilePosition)
    {
        // Create a new tile
        GameObject newTile = new GameObject("Tile " + tiles);
        newTile.AddComponent<MeshRenderer>();
        newTile.AddComponent<MeshFilter>();
        newTile.transform.SetParent(transform.Find("Tiles"));

        // Assign ocean tile mesh renderer properties
        newTile.GetComponent<MeshRenderer>().material = OceanMaterial;
        newTile.GetComponent<MeshFilter>().mesh = Mesh;

        // Get nearest tile position based on size -- assume we have a square?
        float posX = tilePosition.x - tilePosition.x % Size.x;
        float posZ = tilePosition.z - tilePosition.z % Size.y;
        float posY = 0;

        // Assign tile transform properties
        newTile.transform.position = new Vector3(posX, posY, posZ);
        newTile.transform.localScale = new Vector3(1.0f, 1.0f, 1.0f);

        // Add a new tile
        /*if (ActiveTiles != null)
        {
            ActiveTiles.Add(newTile);
            tiles = ActiveTiles.Count;
        }*/

        return newTile; 
    }

    void ClearTileByID(int ID)
    {
        // do something
    }

    // Wipe out tiles
    void ClearAllTiles()
    {
        foreach (GameObject Tile in ActiveTiles)
        {
            Destroy(Tile);
        }

        ActiveTiles.Clear();
        tiles = 0;
    }

    void RunTilingSystem()
    {
        // Do something
        Plane[] frustumPlanes = GeometryUtility.CalculateFrustumPlanes(MainCamera);

        Vector3 cameraPosition = MainCamera.transform.position;
        Vector3 cameraForward = MainCamera.transform.forward;

        int span = 16;
        float tileRadiusX = Size.x;
        float tileRadiusZ = Size.y;

        HashSet<Vector3> newTiles = new HashSet<Vector3>();

        float cullingMargin = 60f; // Adjust the culling margin
        int fanAngle = 120; // this is incredibly slow but it works for now

        for (int i = -fanAngle / 2; i <= fanAngle / 2; i += 2)
        {
            Quaternion rotation = Quaternion.Euler(0, i, 0);
            Vector3 direction = rotation * cameraForward;

            for (int j = -1; j <= span; j++)
            {
                Vector3 tilePosition = cameraPosition + direction * (j * tileRadiusX);
                Bounds tileBounds = new Bounds(tilePosition, new Vector3(tileRadiusX + cullingMargin, 1, tileRadiusZ + cullingMargin));
                if (GeometryUtility.TestPlanesAABB(frustumPlanes, tileBounds))
                {
                    float posX = tilePosition.x - tilePosition.x % Size.x;
                    float posZ = tilePosition.z - tilePosition.z % Size.y;
                    float posY = 0;

                    Vector3 keyPosition = new Vector3(posX, posY, posZ);
                    newTiles.Add(keyPosition);

                    if (!existingTiles.ContainsKey(keyPosition))
                    {
                        // Create the tile
                        GameObject newTile = CreateTile(keyPosition);
                        existingTiles[keyPosition] = newTile;
                    }
                }
            }
        }

        List<Vector3> keysToRemove = new List<Vector3>();
        foreach (var tile in existingTiles)
        {
            if (!newTiles.Contains(tile.Key))
            {
                Destroy(tile.Value);
                keysToRemove.Add(tile.Key);
            }
        }
        foreach(var key in keysToRemove)
        {
            existingTiles.Remove(key);
        }
    }


    // Creates a RenderTexture for use in our compute shaders, later passed into surface shader
    RenderTexture CreateRenderTexture(int width, int height, RenderTextureFormat format, bool useMips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.useMipMap = useMips;
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.autoGenerateMips = false;
        
        rt.Create();
        return rt;
    }

    void AssignTimeOfDay()
    {
        prevTimeOfDay = timeOfDay;
        OceanMaterial.SetFloat("_TimeOfDay", timeOfDay);
        if (SkyMaterial != null)
        {
            SkyMaterial.SetFloat("_TimeOfDay", timeOfDay);
        }
    }

    void InitializeSimulation()
    {
        // Build geometry + material
        CreatePlane();
        CreateMaterial();

        // Tile system setup
        if (ActiveTiles == null)
        {
            ActiveTiles = new List<GameObject>();
        }
        ClearAllTiles();

        // Defines # of threadGroups, (8, 8, 1)
        threadGroupsX = Mathf.CeilToInt(N / 8.0f);
        threadGroupsY = threadGroupsX;

        AssignTimeOfDay();

        // Create the initial spectrum  texture -- should this require mips? Experiment with this
        initialSpectrum = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);
        initialSpectrum.filterMode = FilterMode.Point;

        // Create the spectrum texture
        spectrumTexture = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, false);

        // Create normal map texture
        normalMap = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);

        // Create buffer texture
        FFTBuffer = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, false);

        // idk
        heightMaps = new RenderTexture[cascades]; // idk we're gonna see if this works lol
        for (int i = 0; i < cascades; i++)
        {
            // Create height map texture
            heightMaps[i]  = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);
        }
    }

    // Depending on the direction and ping pong provided in IFFT for loop, runs an IFFT 1-D pass
    void ButterflyPass(bool PingPong) // TODO: For better practice, specify direction of pass (horizontal/vertical)
    {
        OceanComputeShader.SetBool("_PingPong", PingPong);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_ButterflyPass"), threadGroupsX, threadGroupsY, 1);
    }
    
    // Generates h0(k) values, used in spectrum calculations over time
    void GenerateInitialSpectrum()
    {
        // Generate initial Phillips spectrum
        int initialKernel = OceanComputeShader.FindKernel("CS_InitializeSpectrum");
        int initialThreadGroups = Mathf.CeilToInt(N / 8.0f);
        OceanComputeShader.SetTexture(initialKernel, "InitialSpectrum", initialSpectrum);
        OceanComputeShader.Dispatch(initialKernel, initialThreadGroups, initialThreadGroups, 1);
    }


    // Generates h(k) values which is used as an input texture in our IFFT passes
    void GenerateSpectrum()
    {
        threadGroupsX = Mathf.CeilToInt(N / 8.0f);
        threadGroupsY = threadGroupsX;

        // After generating h0k + h0minusk, we compute h_tilde
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_GenerateSpectrum"), "InitialSpectrum", initialSpectrum);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_GenerateSpectrum"), "Spectrum", spectrumTexture);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_GenerateSpectrum"), threadGroupsX, threadGroupsY, 1);
    }

    // Inverts amplitudes by (n,m) s.t (-1)^n * (-1)^m, additionally divides by N^2
    void InversionPermutePass(bool PingPong, RenderTexture PingPong0, RenderTexture PingPong1, int id)
    {
        OceanComputeShader.SetBool("_PingPong", PingPong);
        OceanComputeShader.SetInt("_N", N);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "PingPong0", PingPong0);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "PingPong1", PingPong1);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "Displacement", heightMaps[id]);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_InvertPermute"), threadGroupsX, threadGroupsY, 1);
    }

    // The bulk of our simulation, performs Radix-2 Cooley Tukey IFFT algorithm on GPU via compute shaders
    void IFFT(RenderTexture PingPong0, RenderTexture PingPong1, int id)
    {
        bool PingPong = false;
        int kernelID = OceanComputeShader.FindKernel("CS_ButterflyPass");

        threadGroupsX = Mathf.CeilToInt(N / 16.0f);
        threadGroupsY = threadGroupsX;

        OceanComputeShader.SetTexture(kernelID, "PingPong0", PingPong0);
        OceanComputeShader.SetTexture(kernelID, "PingPong1", PingPong1);

        // Horizontal IFFT Pass
        OceanComputeShader.SetInt("_Direction", 0);

        for (int i = 1; i < N; i <<=1) // Run log2N iterations for each stage in Cooley-Tukey
        {
            OceanComputeShader.SetInt("_Stage", i);
            ButterflyPass(PingPong);
            PingPong = !PingPong;
        }

        // Vertical IFFT Pass
        OceanComputeShader.SetInt("_Direction", 1);

        for (int j = 1; j < N; j <<= 1)
        {
            OceanComputeShader.SetInt("_Stage", j);
            ButterflyPass(PingPong);
            PingPong = !PingPong;
        }

        // Send final results to the inversion/permute pass to write to height map
        InversionPermutePass(PingPong, PingPong0, PingPong1, id);
    }

    void GenerateHeightMap(int id)
    {
        // Set uniforms
        OceanComputeShader.SetInt("_N", N);
        OceanComputeShader.SetInt("_HorizontalPatch", L[id]);
        OceanComputeShader.SetFloat("_Intensity", intensity[id]);
        OceanComputeShader.SetFloat("_WindSpeed", windSpeed[id]);
        OceanComputeShader.SetFloat("_WaveSize", waveSize[id]);

        GenerateInitialSpectrum();

        GenerateSpectrum();
        // Run the inverse FFT to convert frequency data to height data
        // InversionPermutePass is found in here, which later writes to heightMap
        IFFT(spectrumTexture, FFTBuffer, id);

        // Generate mipmaps to reduce artifacts at a far-away distance
        heightMaps[id].GenerateMips();
        OceanMaterial.SetFloat("_TileSize", Size.x);

        string displacementTxt = "_DisplacementTexture" + id;
        OceanMaterial.SetTexture(displacementTxt, heightMaps[id]);
    }

    bool AreParamsDifferent()
    {
        cascades = L.Length;
        bool noChange = (N != prevN);

        for (int i = 0; i < cascades && !noChange; i++)
        {
            noChange = L[i] != prevL[i];
            noChange = noChange || intensity[i] != prevIntensity[i];
            noChange = noChange || windSpeed[i] != windSpeed[i];
            noChange = noChange || waveSize[i] != waveSize[i];
        }

        return noChange;
    }

    bool HasCameraMovedOrRotated()
    {
        return MainCamera.transform.position != previousCameraPosition
            || MainCamera.transform.rotation != previousCameraRotation;
    }

    void AssignNewParams()
    {
        prevN = N;
        for (int i = 0; i < cascades; i++)
        {
            prevL[i] = L[i];
            prevIntensity[i] = intensity[i];
            prevWindSpeed[i] = windSpeed[i];
            prevWaveSize[i] = waveSize[i];
        }
    }

    void AssignShaderUniforms()
    {
        if (OceanMaterial == null)
        {
            return;
        }

        // Assign uv scales for each cascade
        for (int i = 0; i < Scales.Length; i++)
        {
            string id = "_d" + i + "Scale";
            OceanMaterial.SetFloat(id, Scales[i]);
        }

        // Assign T weights
        OceanMaterial.SetFloat("_t0", t0);
        OceanMaterial.SetFloat("_t1", t1);
    }

    void Update()
    {
        // If any adjustments to parameters
        if (AreParamsDifferent())
        {
            // Initialize all textures + compute h0k
            AssignNewParams();
            InitializeSimulation();

            //
            List<Vector3> keysToRemove = new List<Vector3>();
            foreach (var tile in existingTiles)
            {
                Destroy(tile.Value);
                keysToRemove.Add(tile.Key);
            }
            foreach (var key in keysToRemove)
            {
                existingTiles.Remove(key);
            }

            // TilingSystem function somewhere
            RunTilingSystem();
        }

        if (HasCameraMovedOrRotated())
        {
            previousCameraPosition = MainCamera.transform.position;
            previousCameraRotation = MainCamera.transform.rotation;
            //RunTilingSystem();
        }

        AssignShaderUniforms();

        if (prevTimeOfDay != timeOfDay)
        {
            AssignTimeOfDay();
        }

        // Compute h(k) using h0(k) + conjugate of h0(-k)
        OceanComputeShader.SetFloat("_Time", Time.time + 100.0f);
        GenerateHeightMap(0);
        GenerateHeightMap(1);

        //MainCamera.transform.position += new Vector3(0, 0, 1) * 8.0f * Time.deltaTime;
    }
}
