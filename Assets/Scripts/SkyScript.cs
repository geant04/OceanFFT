using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class SkyScript : MonoBehaviour
{
    public Shader skyShader;
    private Material screenQuadMat;
    private CommandBuffer commandBuffer;

    // Initialize screen quad material + command buffer for rendering passes
    void Initialize()
    {
        screenQuadMat = new Material(skyShader);
        screenQuadMat.renderQueue = (int)RenderQueue.Background;
    }
    void RenderQuad()
    {

    }
    void OnRenderObject()
    {
        if (Camera.current != Camera.main)
            return;

        GL.PushMatrix();
        GL.LoadOrtho();

        screenQuadMat.SetPass(0);

        GL.Begin(GL.QUADS);
        GL.TexCoord2(0, 0); GL.Vertex3(0, 0, 0);
        GL.TexCoord2(1, 0); GL.Vertex3(1, 0, 0);
        GL.TexCoord2(1, 1); GL.Vertex3(1, 1, 0);
        GL.TexCoord2(0, 1); GL.Vertex3(0, 1, 0);
        GL.End();

        GL.PopMatrix();
    }

    // Start is called before the first frame update
    void Start()
    {
        Initialize();

    }   

    // Update is called once per frame
    void Update()
    {
        
    }
}
