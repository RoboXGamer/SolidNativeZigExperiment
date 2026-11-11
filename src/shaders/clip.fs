#version 330
in vec2 fragTexCoord;
out vec4 finalColor;
uniform sampler2D texture0;
uniform mat4 inverseWorld;
uniform vec4 box;
uniform vec4 radii;
uniform vec2 axes;
uniform vec2 resolution;
void main() {
    vec2 world=vec2(gl_FragCoord.x,resolution.y-gl_FragCoord.y);
    vec2 p=(inverseWorld*vec4(world,0,1)).xy-box.xy;
    float coverage=1.0;
    if(axes.x>0.5 && (p.x<0.0 || p.x>=box.z)) coverage=0.0;
    if(axes.y>0.5 && (p.y<0.0 || p.y>=box.w)) coverage=0.0;
    if(axes.x>0.5 && axes.y>0.5) {
        bool right=p.x>box.z*0.5, bottom=p.y>box.w*0.5;
        float r=bottom ? (right?radii.z:radii.w) : (right?radii.y:radii.x);
        vec2 center=vec2(right?box.z-r:r,bottom?box.w-r:r);
        vec2 d=abs(p-center);
        if(d.x<r && d.y<r) coverage*=1.0-smoothstep(r-0.5,r+0.5,length(d));
    }
    finalColor=vec4(vec3(1.0),texture(texture0,fragTexCoord).a*coverage);
}
