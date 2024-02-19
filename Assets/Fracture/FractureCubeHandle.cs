using System;
using UnityEngine;

public class FractureCubeHandle : MonoBehaviour
{
    // public Material Target;
    [Min(0)] public float Radius = 1;

    private string positionProperty = "_Pos";
    private string radiusProperty = "_Radius";

    // Update is called once per frame
    void Update()
    {
        // Target.SetVector(positionProperty, transform.position);
        // Target.SetFloat(radiusProperty, Radius);
        
        Shader.SetGlobalVector(positionProperty, transform.position);
        Shader.SetGlobalFloat(radiusProperty, Radius);
    }

    private void OnDrawGizmosSelected()
    {
        Gizmos.color = Color.green;
        Gizmos.DrawWireSphere(transform.position, Radius);
    }
}
