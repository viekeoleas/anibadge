import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const SIZE = 800;

const clamp = (value: number) => Math.max(0, Math.min(1, value));

const pulse = (frame: number, start: number, peak: number, end: number) => {
  if (frame <= start || frame >= end) return 0;
  if (frame <= peak) return (frame - start) / (peak - start);
  return (end - frame) / (end - peak);
};

const ToyotaMark: React.FC<{
  opacity: number;
  scaleX: number;
  scaleY: number;
  glitch: number;
}> = ({opacity, scaleX, scaleY, glitch}) => {
  const frame = useCurrentFrame();
  const jitterX = Math.sin(frame * 7.31) * glitch * 18;
  const jitterY = Math.cos(frame * 4.77) * glitch * 7;

  return (
    <>
      <div
        style={{
          position: "absolute",
          left: 178,
          top: 178,
          width: 444,
          height: 444,
          borderRadius: "50%",
          background:
            "radial-gradient(circle, rgba(255,20,55,0.34), rgba(255,0,40,0.08) 42%, transparent 70%)",
          filter: "blur(18px)",
          opacity: opacity * 0.8,
          scale: `${scaleX * 1.08} ${scaleY * 1.08}`,
        }}
      />
      {glitch > 0.02 &&
        Array.from({length: 7}).map((_, index) => (
          <Img
            key={index}
            src={staticFile("toyota-logo.png")}
            style={{
              position: "absolute",
              left: 170 + jitterX * (index % 2 === 0 ? 1 : -1),
              top: 170 + jitterY,
              width: 460,
              height: 460,
              opacity: opacity * glitch * 0.58,
              mixBlendMode: "screen",
              filter:
                index % 2 === 0
                  ? "hue-rotate(165deg) saturate(2)"
                  : "saturate(1.8) brightness(1.3)",
              clipPath: `inset(${index * 13}% 0 ${87 - index * 13}% 0)`,
              scale: `${scaleX} ${scaleY}`,
            }}
          />
        ))}
      <Img
        src={staticFile("toyota-logo.png")}
        style={{
          position: "absolute",
          left: 170 + jitterX * 0.18,
          top: 170 + jitterY * 0.18,
          width: 460,
          height: 460,
          opacity,
          mixBlendMode: "screen",
          filter: "saturate(1.25) brightness(1.12)",
          scale: `${scaleX} ${scaleY}`,
        }}
      />
    </>
  );
};

const CyberEye: React.FC<{
  opacity: number;
  openness: number;
  gazeX: number;
  gazeY: number;
  dilation: number;
  glitch: number;
}> = ({opacity, openness, gazeX, gazeY, dilation, glitch}) => {
  const frame = useCurrentFrame();
  const jitter = Math.sin(frame * 9.7) * glitch * 13;

  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox="0 0 800 800"
      style={{
        position: "absolute",
        inset: 0,
        opacity,
        scale: `1 ${openness}`,
        translate: `${jitter}px 0px`,
      }}
    >
      <defs>
        <radialGradient id="iris-red" cx="50%" cy="46%" r="58%">
          <stop offset="0" stopColor="#fff" stopOpacity="0.94" />
          <stop offset="0.12" stopColor="#ff6b7e" />
          <stop offset="0.42" stopColor="#ec1238" />
          <stop offset="0.78" stopColor="#5f0016" />
          <stop offset="1" stopColor="#080206" />
        </radialGradient>
        <linearGradient id="eye-shell" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#24000a" />
          <stop offset="0.48" stopColor="#080308" />
          <stop offset="1" stopColor="#160008" />
        </linearGradient>
        <filter id="eye-glow" x="-80%" y="-80%" width="260%" height="260%">
          <feGaussianBlur stdDeviation="8" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
        <clipPath id="eye-clip">
          <path d="M116 400 Q260 194 400 194 Q540 194 684 400 Q540 606 400 606 Q260 606 116 400Z" />
        </clipPath>
      </defs>

      <path
        d="M116 400 Q260 194 400 194 Q540 194 684 400 Q540 606 400 606 Q260 606 116 400Z"
        fill="url(#eye-shell)"
        stroke="#ff1744"
        strokeWidth="9"
        filter="url(#eye-glow)"
      />
      <path
        d="M132 400 Q268 218 400 218 Q532 218 668 400"
        fill="none"
        stroke="rgba(255,255,255,0.72)"
        strokeWidth="3"
      />
      <g clipPath="url(#eye-clip)">
        {Array.from({length: 24}).map((_, index) => {
          const angle = (index / 24) * Math.PI * 2;
          return (
            <line
              key={index}
              x1={400 + gazeX + Math.cos(angle) * 84}
              y1={400 + gazeY + Math.sin(angle) * 84}
              x2={400 + gazeX + Math.cos(angle) * 142}
              y2={400 + gazeY + Math.sin(angle) * 142}
              stroke={index % 3 === 0 ? "#ff7189" : "#8a0b28"}
              strokeWidth={index % 3 === 0 ? 4 : 2}
              opacity={0.48}
            />
          );
        })}
        <circle
          cx={400 + gazeX}
          cy={400 + gazeY}
          r="128"
          fill="url(#iris-red)"
          stroke="#ff4260"
          strokeWidth="5"
          filter="url(#eye-glow)"
        />
        <circle
          cx={400 + gazeX}
          cy={400 + gazeY}
          r="99"
          fill="none"
          stroke="rgba(255,255,255,0.34)"
          strokeWidth="3"
          strokeDasharray="20 15"
          strokeDashoffset={-frame * 2.4}
        />
        <ellipse
          cx={400 + gazeX}
          cy={400 + gazeY}
          rx={28 * dilation}
          ry={86 * dilation}
          fill="#030104"
          stroke="#ff1744"
          strokeWidth="5"
          filter="url(#eye-glow)"
        />
        <ellipse
          cx={370 + gazeX}
          cy={356 + gazeY}
          rx="18"
          ry="29"
          fill="rgba(255,255,255,0.92)"
        />
        <circle
          cx={421 + gazeX}
          cy={440 + gazeY}
          r="8"
          fill="rgba(255,255,255,0.7)"
        />
      </g>
      <path
        d="M116 400 Q260 606 400 606 Q540 606 684 400"
        fill="none"
        stroke="#8c0927"
        strokeWidth="7"
      />
    </svg>
  );
};

const EclipsePortal: React.FC<{
  opacity: number;
  scale: number;
  rotation: number;
  flash: number;
}> = ({opacity, scale, rotation, flash}) => {
  const frame = useCurrentFrame();

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        opacity,
        scale,
      }}
    >
      <svg
        width={SIZE}
        height={SIZE}
        viewBox="0 0 800 800"
        style={{position: "absolute", inset: 0}}
      >
        <defs>
          <radialGradient id="portal-core" cx="50%" cy="50%" r="50%">
            <stop offset="0" stopColor="#000" />
            <stop offset="0.52" stopColor="#020102" />
            <stop offset="0.72" stopColor="#f10d39" />
            <stop offset="0.82" stopColor="#ff9cac" />
            <stop offset="0.9" stopColor="#87001e" />
            <stop offset="1" stopColor="transparent" />
          </radialGradient>
          <linearGradient id="tunnel-line" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#ff1744" stopOpacity="0.05" />
            <stop offset="1" stopColor="#ff1744" stopOpacity="0.8" />
          </linearGradient>
          <filter id="portal-glow" x="-70%" y="-70%" width="240%" height="240%">
            <feGaussianBlur stdDeviation="10" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {Array.from({length: 10}).map((_, index) => {
          const progress = (index / 10 + frame / 80) % 1;
          return (
            <ellipse
              key={index}
              cx="400"
              cy={400 + progress * 190}
              rx={70 + progress * 360}
              ry={20 + progress * 152}
              fill="none"
              stroke="url(#tunnel-line)"
              strokeWidth={1 + progress * 3}
              opacity={0.12 + progress * 0.68}
            />
          );
        })}
        {[-340, -250, -165, -86, 86, 165, 250, 340].map((x) => (
          <line
            key={x}
            x1="400"
            y1="400"
            x2={400 + x}
            y2="790"
            stroke="url(#tunnel-line)"
            strokeWidth="2"
            opacity="0.48"
          />
        ))}

        <g style={{rotate: `${rotation}deg`, transformOrigin: "400px 400px"}}>
          {Array.from({length: 12}).map((_, index) => {
            const angle = index * 30;
            return (
              <path
                key={index}
                d="M400 130 C432 174 446 228 424 294 L400 340 L376 294 C354 228 368 174 400 130Z"
                fill={index % 2 === 0 ? "rgba(255,23,68,0.78)" : "rgba(255,255,255,0.18)"}
                stroke={index % 2 === 0 ? "#ff1744" : "#731029"}
                strokeWidth="2"
                style={{rotate: `${angle}deg`, transformOrigin: "400px 400px"}}
              />
            );
          })}
        </g>
        <circle
          cx="400"
          cy="400"
          r="184"
          fill="url(#portal-core)"
          filter="url(#portal-glow)"
        />
        <circle
          cx="400"
          cy="400"
          r="205"
          fill="none"
          stroke="#ff1744"
          strokeWidth="3"
          strokeDasharray="42 20 8 18"
          strokeDashoffset={frame * 5}
          opacity="0.82"
        />
        <circle
          cx="400"
          cy="400"
          r="236"
          fill="none"
          stroke="rgba(255,255,255,0.42)"
          strokeWidth="2"
          strokeDasharray="7 23"
          strokeDashoffset={-frame * 3}
        />
      </svg>

      <div
        style={{
          position: "absolute",
          left: 78,
          right: 78,
          top: 397,
          height: 6,
          background:
            "linear-gradient(90deg, transparent, #ff1744, #fff, #ff1744, transparent)",
          boxShadow: "0 0 28px #ff1744",
          opacity: 0.3 + flash * 0.7,
          scale: `1 ${1 + flash * 4}`,
        }}
      />
    </div>
  );
};

const GlitchBars: React.FC<{power: number}> = ({power}) => {
  const frame = useCurrentFrame();
  if (power < 0.01) return null;

  return (
    <>
      {Array.from({length: 9}).map((_, index) => {
        const width = 160 + ((index * 97) % 390);
        const left = ((index * 131 + frame * 29) % 620) - 40;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left,
              top: 90 + index * 67,
              width,
              height: index % 3 === 0 ? 6 : 2,
              backgroundColor: index % 2 === 0 ? "#ff1744" : "#38e8ff",
              boxShadow:
                index % 2 === 0 ? "0 0 16px #ff1744" : "0 0 16px #38e8ff",
              opacity: power * (0.35 + (index % 4) * 0.15),
              translate: `${Math.sin(frame * 5 + index) * power * 54}px 0px`,
            }}
          />
        );
      })}
    </>
  );
};

export const ToyotaEyePortal: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;

  const firstGlitch = pulse(frame, 32, 47, 61);
  const blinkGlitch = pulse(frame, 126, 139, 151);
  const returnGlitch = pulse(frame, 205, 218, 232);
  const glitch = Math.max(firstGlitch, blinkGlitch, returnGlitch);

  const logoOut = interpolate(frame, [31, 58], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.55, 0, 0.8, 0.2),
  });
  const logoBack = interpolate(frame, [207, 234], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });
  const returnOvershoot = interpolate(frame, [207, 224, durationInFrames], [0, 0.07, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });
  const logoOpacity = Math.max(logoOut, logoBack);
  const logoScaleY = Math.max(
    interpolate(frame, [30, 58], [1, 0.08], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.55, 0, 0.8, 0.2),
    }) * logoOut,
    interpolate(frame, [207, 234], [0.08, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.16, 1, 0.3, 1),
    }) * logoBack,
  );

  const eyeOpacity = Math.min(
    interpolate(frame, [39, 60], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.16, 1, 0.3, 1),
    }),
    interpolate(frame, [132, 148], [1, 0], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.7, 0, 0.84, 0),
    }),
  );
  const blink = interpolate(frame, [126, 136, 141, 149], [1, 0.035, 0.035, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.45, 0, 0.55, 1),
  });
  const gazeX = interpolate(
    frame,
    [60, 72, 88, 100, 114, 126, 134],
    [0, -68, -68, 72, 72, 0, 0],
    {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.45, 0, 0.55, 1),
    },
  );
  const gazeY = Math.sin(frame * 0.16) * 7 * clamp(eyeOpacity);
  const dilation = 0.86 + Math.max(0, Math.sin((frame - 58) * 0.13)) * 0.24;

  const portalOpacity = Math.min(
    interpolate(frame, [135, 154], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.16, 1, 0.3, 1),
    }),
    interpolate(frame, [204, 226], [1, 0], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.7, 0, 0.84, 0),
    }),
  );
  const portalScale = interpolate(frame, [135, 160, 204, 226], [0.14, 1, 1.05, 0.16], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });
  const flash = pulse(frame, 164, 172, 181);
  const backgroundWave = (Math.sin(phase * Math.PI * 2) + 1) / 2;

  return (
    <AbsoluteFill style={{backgroundColor: "#000"}}>
      <AbsoluteFill
        style={{
          borderRadius: "50%",
          overflow: "hidden",
          background: `radial-gradient(circle at 50% 50%, rgba(168,0,35,${0.16 + backgroundWave * 0.1}) 0%, #100108 38%, #030205 72%, #000 100%)`,
        }}
      >
        <div
          style={{
            position: "absolute",
            left: 86,
            top: 86,
            width: 628,
            height: 628,
            borderRadius: "50%",
            border: "2px solid rgba(255,23,68,0.24)",
            borderLeftColor: "transparent",
            borderRightColor: "transparent",
            rotate: `${phase * 360}deg`,
            boxShadow: "0 0 20px rgba(255,23,68,0.22)",
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 118,
            top: 118,
            width: 564,
            height: 564,
            borderRadius: "50%",
            border: "1px dashed rgba(255,255,255,0.18)",
            rotate: `${-phase * 360}deg`,
          }}
        />

        {Array.from({length: 14}).map((_, index) => {
          const angle = phase * Math.PI * 2 + (index * Math.PI * 2) / 14;
          const radius = index % 3 === 0 ? 330 : 296;
          const length = index % 3 === 0 ? 68 : 28;
          return (
            <div
              key={index}
              style={{
                position: "absolute",
                left: 400 + Math.cos(angle) * radius - length / 2,
                top: 400 + Math.sin(angle) * radius - 1,
                width: length,
                height: index % 3 === 0 ? 3 : 1,
                borderRadius: 99,
                backgroundColor: index % 4 === 0 ? "#41e8ff" : "#ff1744",
                boxShadow:
                  index % 4 === 0 ? "0 0 12px #41e8ff" : "0 0 12px #ff1744",
                opacity: 0.28 + backgroundWave * 0.34,
                rotate: `${(angle * 180) / Math.PI + 90}deg`,
              }}
            />
          );
        })}

        <ToyotaMark
          opacity={logoOpacity}
          scaleX={0.96 + returnOvershoot}
          scaleY={logoScaleY}
          glitch={glitch}
        />
        <CyberEye
          opacity={eyeOpacity}
          openness={blink}
          gazeX={gazeX}
          gazeY={gazeY}
          dilation={dilation}
          glitch={glitch}
        />
        <EclipsePortal
          opacity={portalOpacity}
          scale={portalScale}
          rotation={(frame - 138) * 4.2}
          flash={flash}
        />

        <div
          style={{
            position: "absolute",
            inset: 0,
            backgroundImage:
              "repeating-linear-gradient(0deg, transparent 0px, transparent 6px, rgba(255,255,255,0.06) 7px)",
            opacity: 0.16 + glitch * 0.18,
          }}
        />
        <GlitchBars power={glitch} />
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: `rgba(255,255,255,${flash * 0.32})`,
          }}
        />
        <div
          style={{
            position: "absolute",
            inset: 0,
            background:
              "radial-gradient(circle, transparent 48%, rgba(10,0,4,0.72) 78%, #000 100%)",
          }}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
