#version 330
in vec2 fragTexCoord;
out vec4 finalColor;
uniform sampler2D texture0;
uniform sampler2D maskTexture;
uniform float opacity;
void main() {
    vec4 color=texture(texture0,fragTexCoord);
    finalColor=color*(texture(maskTexture,fragTexCoord).a*opacity);
}
