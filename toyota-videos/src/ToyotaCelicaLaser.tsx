import type {CSSProperties, ReactNode} from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const progress = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

const windowed = (
  frame: number,
  fadeInStart: number,
  fadeInEnd: number,
  fadeOutStart: number,
  fadeOutEnd: number,
) =>
  Math.min(
    progress(frame, fadeInStart, fadeInEnd),
    1 - progress(frame, fadeOutStart, fadeOutEnd),
  );

const Badge: React.FC<{children: ReactNode}> = ({children}) => (
  <AbsoluteFill style={{backgroundColor: "#000"}}>
    <AbsoluteFill
      style={{
        overflow: "hidden",
        borderRadius: "50%",
        background:
          "radial-gradient(circle at 50% 45%,#170106 0%,#080106 42%,#010102 76%,#000 100%)",
        fontFamily: "Arial, sans-serif",
      }}
    >
      {children}
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(circle at 50% 49%,transparent 49%,rgba(0,0,0,0.44) 72%,#000 100%)",
          pointerEvents: "none",
        }}
      />
    </AbsoluteFill>
  </AbsoluteFill>
);

const CarImage: React.FC<{style?: CSSProperties}> = ({style}) => (
  <Img
    src={staticFile("celica-front-cutout-v2.png")}
    style={{
      position: "absolute",
      left: 18,
      top: 22,
      width: 764,
      height: 764,
      objectFit: "contain",
      ...style,
    }}
  />
);

const PerspectiveFloor: React.FC<{opacity: number; phase: number}> = ({
  opacity,
  phase,
}) => (
  <svg
    viewBox="0 0 800 800"
    style={{position: "absolute", inset: 0, opacity}}
  >
    <defs>
      <linearGradient id="laser-floor" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#ff3656" stopOpacity="0" />
        <stop offset="1" stopColor="#ff173d" stopOpacity="0.66" />
      </linearGradient>
      <filter id="floor-glow" x="-100%" y="-100%" width="300%" height="300%">
        <feGaussianBlur stdDeviation="4" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </defs>
    {Array.from({length: 9}).map((_, index) => {
      const p = (index / 9 + phase * 0.44) % 1;
      return (
        <ellipse
          key={index}
          cx="400"
          cy={555 + p * 215}
          rx={72 + p * 360}
          ry={8 + p * 86}
          fill="none"
          stroke="url(#laser-floor)"
          strokeWidth={1 + p * 1.8}
          opacity={0.08 + p * 0.46}
        />
      );
    })}
    {[-380, -270, -170, -82, 82, 170, 270, 380].map((x) => (
      <line
        key={x}
        x1="400"
        y1="545"
        x2={400 + x}
        y2="800"
        stroke="#ff284a"
        strokeWidth="1.5"
        opacity="0.22"
      />
    ))}
    <ellipse
      cx="400"
      cy="595"
      rx="315"
      ry="70"
      fill="none"
      stroke="#ff3152"
      strokeWidth="2"
      opacity="0.48"
      filter="url(#floor-glow)"
    />
  </svg>
);

export const ToyotaCelicaLaserResurrection: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const scan = progress(frame, 12, 73);
  const materialize = progress(frame, 34, 88);
  const hero = windowed(frame, 61, 88, 198, 231);
  const shutdown = progress(frame, 207, 239);
  const ignition = windowed(frame, 79, 98, 176, 207);
  const ambience = Math.sin(phase * Math.PI * 2);
  const scanY = interpolate(scan, [0, 1], [152, 670]);
  const carX = Math.sin(phase * Math.PI * 2) * 7 * hero;
  const carY = Math.cos(phase * Math.PI * 2) * 2.5 * hero;
  const carScale = 0.985 + hero * 0.025 + ambience * 0.006 * hero;
  const revealTop = 100 - materialize * 100;
  const logoOpacity = windowed(frame, 101, 126, 169, 197);

  return (
    <Badge>
      <AbsoluteFill
        style={{
          opacity: hero,
          background: `radial-gradient(ellipse at 52% 57%,rgba(255,18,55,${0.18 + ignition * 0.12}) 0%,transparent 56%)`,
        }}
      />

      <PerspectiveFloor opacity={hero * 0.66} phase={phase} />

      {Array.from({length: 24}).map((_, index) => {
        const angle = index * 2.399 + phase * Math.PI * 2 * (index % 2 ? 1 : -1);
        const radius = 190 + ((index * 47) % 170);
        const flicker = 0.32 + 0.68 * Math.max(0, Math.sin(frame * 0.19 + index));
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + Math.cos(angle) * radius,
              top: 404 + Math.sin(angle) * radius * 0.82,
              width: index % 5 === 0 ? 22 : 9,
              height: index % 5 === 0 ? 2 : 1,
              borderRadius: 99,
              background: index % 6 === 0 ? "#fff" : "#ff3152",
              boxShadow: "0 0 10px #ff2347",
              opacity: hero * flicker * 0.6,
              rotate: `${(angle * 180) / Math.PI}deg`,
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 84,
          top: 530,
          width: 632,
          height: 122,
          borderRadius: "50%",
          background: "rgba(255,10,42,0.3)",
          filter: "blur(38px)",
          opacity: hero * 0.54,
          scale: 0.95 + ignition * 0.12,
        }}
      />

      <CarImage
        style={{
          opacity: hero * 0.24,
          filter: "brightness(0) drop-shadow(0 20px 20px rgba(255,15,45,0.82))",
          translate: `${carX}px ${carY + 16}px`,
          scale: carScale * 1.015,
        }}
      />

      <CarImage
        style={{
          opacity: Math.max(materialize, hero) * (1 - shutdown),
          clipPath: `inset(${revealTop}% 0 0 0)`,
          filter: `saturate(${1.03 + ignition * 0.18}) contrast(${1.02 + ignition * 0.06}) drop-shadow(0 22px 22px rgba(0,0,0,0.82)) drop-shadow(0 0 ${8 + ignition * 12}px rgba(255,26,58,0.32))`,
          translate: `${carX}px ${carY}px`,
          scale: carScale,
        }}
      />

      <CarImage
        style={{
          opacity: (1 - materialize) * 0.68 * (1 - shutdown),
          clipPath: `inset(${Math.max(0, revealTop - 4)}% 0 ${Math.max(0, 96 - revealTop)}% 0)`,
          filter:
            "grayscale(1) brightness(2.4) contrast(1.8) sepia(1) saturate(5) hue-rotate(318deg) drop-shadow(0 0 9px #ff2449)",
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: scanY,
          height: 3,
          background:
            "linear-gradient(90deg,transparent 6%,rgba(255,44,77,0.22) 18%,#fff 50%,rgba(255,31,68,0.42) 82%,transparent 94%)",
          boxShadow: "0 0 10px #fff,0 0 28px #ff153e,0 0 62px rgba(255,20,58,0.68)",
          opacity: (1 - progress(frame, 72, 84)) * (1 - shutdown),
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 70,
          right: 70,
          top: scanY - 48,
          height: 96,
          background:
            "linear-gradient(180deg,transparent,rgba(255,20,54,0.16),transparent)",
          mixBlendMode: "screen",
          opacity: 1 - progress(frame, 72, 84),
        }}
      />

      {[
        {left: 91, top: 411, width: 80, rotate: -12},
        {left: 325, top: 396, width: 112, rotate: -15},
      ].map((light, index) => (
        <div
          key={light.left}
          style={{
            position: "absolute",
            left: light.left + carX,
            top: light.top + carY,
            width: light.width,
            height: 24,
            borderRadius: "50%",
            rotate: `${light.rotate}deg`,
            background:
              "radial-gradient(ellipse,#fff 0%,rgba(255,245,242,0.88) 12%,rgba(255,47,74,0.42) 45%,transparent 72%)",
            filter: `blur(${index === 0 ? 3 : 4}px)`,
            boxShadow: "0 0 24px rgba(255,255,255,0.86),0 0 54px #ff2148",
            opacity: ignition * (0.58 + Math.max(0, Math.sin(frame * 0.37)) * 0.18),
            scale: carScale,
          }}
        />
      ))}

      <Img
        src={staticFile("toyota-logo-transparent.png")}
        style={{
          position: "absolute",
          left: 340,
          top: 88,
          width: 120,
          height: 120,
          objectFit: "contain",
          opacity: logoOpacity * 0.76,
          filter: "drop-shadow(0 0 16px rgba(255,36,65,0.9))",
          scale: 0.86 + logoOpacity * 0.14,
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 120,
          right: 120,
          bottom: 92,
          textAlign: "center",
          color: "#fff",
          fontSize: 34,
          fontWeight: 800,
          letterSpacing: 13,
          textShadow: "0 0 18px rgba(255,24,58,0.9)",
          opacity: logoOpacity,
          translate: `0 ${12 - logoOpacity * 12}px`,
        }}
      >
        CELICA
      </div>

      <div
        style={{
          position: "absolute",
          left: 170,
          right: 170,
          bottom: 63,
          textAlign: "center",
          color: "#ff4967",
          fontFamily: "Consolas, monospace",
          fontSize: 13,
          fontWeight: 700,
          letterSpacing: 5,
          opacity: logoOpacity * 0.9,
        }}
      >
        T230 / 2003
      </div>

      <AbsoluteFill
        style={{
          opacity: 0.12 * hero,
          backgroundImage:
            "repeating-linear-gradient(0deg,transparent 0,transparent 5px,rgba(255,255,255,0.08) 6px)",
          pointerEvents: "none",
        }}
      />

      <AbsoluteFill
        style={{
          backgroundColor: "#000",
          opacity: Math.max(1 - progress(frame, 0, 12), shutdown),
          pointerEvents: "none",
        }}
      />
    </Badge>
  );
};
