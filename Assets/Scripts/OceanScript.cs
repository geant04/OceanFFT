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
    [SerializeField] Vector2 Size = new Vector2(1,1);
    [SerializeField] int planeResolution = 1;
    [SerializeField] int N = 32;
    [SerializeField] int L = 64;
    [SerializeField] float intensity;
    [SerializeField] float windSpeed;
    [SerializeField] Vector2 windDirection;
    [Range(0.0f, 1.0f)] public float timeOfDay;
    
    // RenderTextures
    private RenderTexture heightMap,
                          normalMap,
                          initialSpectrum,
                          spectrumTexture,
                          FFTBuffer,
                          butterfly;
    
    // Misc.
    Vector3[] vertices;
    private int prevN;
    private int prevL;
    private float prevIntensity;
    private float prevWindSpeed;
    private float prevTimeOfDay;

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

    void CreateTile(Vector3 tilePosition)
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
        float posY = tilePosition.y - tilePosition.y % Size.y;
        float posZ = 0;

        // Assign tile transform properties
        newTile.transform.position = new Vector3(posX, posY, posZ);
        newTile.transform.localScale = new Vector3(1.0f, 1.0f, 1.0f);

        // Add a new tile
        if (ActiveTiles != null)
        {
            ActiveTiles.Add(newTile);
            tiles = ActiveTiles.Count;
        }
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
        // Set previous values for updates; will check for these when we change something
        prevN = N;
        prevL = L;
        prevIntensity = intensity;
        prevWindSpeed = windSpeed;

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

        // Set uniforms
        OceanComputeShader.SetInt("_N", N);
        OceanComputeShader.SetInt("_HorizontalPatch", L);
        OceanComputeShader.SetFloat("_Intensity", intensity);
        OceanComputeShader.SetFloat("_WindSpeed", windSpeed);
        AssignTimeOfDay();

        // Create the initial spectrum  texture -- should this require mips? Experiment with this
        initialSpectrum = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);
        initialSpectrum.filterMode = FilterMode.Point;

        // Generate initial Phillips spectrum
        int initialKernel = OceanComputeShader.FindKernel("CS_InitializeSpectrum");
        int initialThreadGroups = Mathf.CeilToInt(N / 8.0f);
        OceanComputeShader.SetTexture(initialKernel, "InitialSpectrum", initialSpectrum);
        OceanComputeShader.Dispatch(initialKernel, initialThreadGroups, initialThreadGroups, 1);

        // Create the spectrum texture
        spectrumTexture = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, false);

        // Create height map texture
        heightMap = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);

        // Create normal map texture
        normalMap = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);

        // Create buffer texture
        FFTBuffer = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, false);
    }

    // Depending on the direction and ping pong provided in IFFT for loop, runs an IFFT 1-D pass
    void ButterflyPass(bool PingPong) // TODO: For better practice, specify direction of pass (horizontal/vertical)
    {
        OceanComputeShader.SetBool("_PingPong", PingPong);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_ButterflyPass"), threadGroupsX, threadGroupsY, 1);
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
    void InversionPermutePass(bool PingPong, RenderTexture PingPong0, RenderTexture PingPong1)
    {
        OceanComputeShader.SetBool("_PingPong", PingPong);
        OceanComputeShader.SetInt("_N", N);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "PingPong0", PingPong0);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "PingPong1", PingPong1);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "Displacement", heightMap);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_InvertPermute"), threadGroupsX, threadGroupsY, 1);
    }

    // The bulk of our simulation, performs Radix-2 Cooley Tukey IFFT algorithm on GPU via compute shaders
    void IFFT(RenderTexture PingPong0, RenderTexture PingPong1)
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
        InversionPermutePass(PingPong, PingPong0, PingPong1);
    }

    // Requires heightmap to be made; generates the normals from a heightmap
    void GenerateNormals()
    {
        int kernelID = OceanComputeShader.FindKernel("CS_CentralDifferentiation");
        OceanComputeShader.SetTexture(kernelID, "Normals", normalMap);
        OceanComputeShader.SetTexture(kernelID, "Displacement", heightMap);
        OceanComputeShader.Dispatch(kernelID, threadGroupsX, threadGroupsY, 1);
    }

    void Update()
    {
        // If any adjustments to parameters
        if ((N != prevN) 
            || (L != prevL) 
            || (intensity != prevIntensity) 
            || (windSpeed != prevWindSpeed)
           )
        {
            // Initialize all textures + compute h0k
            InitializeSimulation();

            // TilingSystem function somewhere
            CreateTile(MainCamera.transform.position);
        }

        if (prevTimeOfDay != timeOfDay)
        {
            AssignTimeOfDay();
        }

        // Compute h(k) using h0(k) + conjugate of h0(-k)
        OceanComputeShader.SetFloat("_Time", Time.time);
        GenerateSpectrum();

        // Run the inverse FFT to convert frequency data to height data
        // InversionPermutePass is found in here, which later writes to heightMap
        IFFT(spectrumTexture, FFTBuffer);

        // Generate mipmaps to reduce artifacts at a far-away distance
        heightMap.GenerateMips();
        OceanMaterial.SetFloat("_TileSize", Size.x);
        OceanMaterial.SetTexture("_DisplacementTexture", heightMap);
    }
}
