#version 330
in vec2 fragTexCoord;
out vec4 finalColor;
uniform sampler2D texture0;
uniform mat4 inverseWorld;
uniform vec4 box;
uniform vec4 radiiX;
uniform vec4 radiiY;
uniform vec2 axes;
uniform vec2 resolution;
void main() {
    vec2 world=vec2(gl_FragCoord.x,resolution.y-gl_FragCoord.y);
    vec2 p=(inverseWorld*vec4(world,0,1)).xy-box.xy;
    float coverage=1.0;
    if(axes.x>0.5 && (p.x<0.0 || p.x>=box.z)) coverage=0.0;
    if(axes.y>0.5 && (p.y<0.0 || p.y>=box.w)) coverage=0.0;
    if(axes.x>0.5 && axes.y>0.5) {
        for(int i=0;i<4;i++) {
            bool right=i==1 || i==2, bottom=i==2 || i==3;
            vec2 radius=vec2(radiiX[i],radiiY[i]);
            vec2 d=vec2(right?box.z-p.x:p.x,bottom?box.w-p.y:p.y);
            if(radius.x>0.0 && radius.y>0.0 && d.x<radius.x && d.y<radius.y) {
                float edge=length((d-radius)/radius)-1.0;
                float aa=max(fwidth(edge),0.00001);
                coverage*=1.0-smoothstep(-aa*0.5,aa*0.5,edge);
            }
        }
    }
    finalColor=vec4(vec3(1.0),texture(texture0,fragTexCoord).a*coverage);
}
