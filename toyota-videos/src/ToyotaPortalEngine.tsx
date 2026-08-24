import type {CSSProperties, ReactNode} from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const ease = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

const fadeWindow = (
  frame: number,
  inStart: number,
  inEnd: number,
  outStart: number,
  outEnd: number,
) => Math.min(ease(frame, inStart, inEnd), 1 - ease(frame, outStart, outEnd));

const Stage: React.FC<{children: ReactNode}> = ({children}) => (
  <AbsoluteFill style={{backgroundColor: "#000"}}>
    <AbsoluteFill
      style={{
        overflow: "hidden",
        borderRadius: "50%",
        background:
          "radial-gradient(circle at 50% 47%,#1d0209 0%,#070105 44%,#010102 76%,#000 100%)",
      }}
    >
      {children}
      <AbsoluteFill
        style={{
          pointerEvents: "none",
          background:
            "radial-gradient(circle at 50% 50%,transparent 51%,rgba(0,0,0,0.38) 72%,#000 100%)",
        }}
      />
    </AbsoluteFill>
  </AbsoluteFill>
);

type LogoMaskProps = {
  size: number;
  fill: string;
  opacity?: number;
  scale?: number;
  rotate?: number;
  x?: number;
  y?: number;
  filter?: string;
  clipPath?: string;
  mixBlendMode?: CSSProperties["mixBlendMode"];
};

const LogoMask: React.FC<LogoMaskProps> = ({
  size,
  fill,
  opacity = 1,
  scale = 1,
  rotate = 0,
  x = 0,
  y = 0,
  filter,
  clipPath,
  mixBlendMode,
}) => {
  const logo = `url(${staticFile("toyota-logo-transparent.png")})`;
  return (
    <div
      style={{
        position: "absolute",
        left: (800 - size) / 2,
        top: (800 - size) / 2,
        width: size,
        height: size,
        background: fill,
        WebkitMaskImage: logo,
        maskImage: logo,
        WebkitMaskPosition: "center",
        maskPosition: "center",
        WebkitMaskRepeat: "no-repeat",
        maskRepeat: "no-repeat",
        WebkitMaskSize: "contain",
        maskSize: "contain",
        opacity,
        scale,
        rotate: `${rotate}deg`,
        translate: `${x}px ${y}px`,
        filter,
        clipPath,
        mixBlendMode,
      }}
    />
  );
};

const CoreRings: React.FC<{opacity: number; spin: number}> = ({opacity, spin}) => (
  <>
    {[742, 666, 582].map((size, index) => (
      <div
        key={size}
        style={{
          position: "absolute",
          left: (800 - size) / 2,
          top: (800 - size) / 2,
          width: size,
          height: size,
          borderRadius: "50%",
          border: `${index === 1 ? 2 : 1}px ${index === 1 ? "dashed" : "solid"} rgba(255,38,72,${0.24 + index * 0.1})`,
          borderTopColor: index === 1 ? "rgba(255,255,255,0.8)" : undefined,
          borderBottomColor: "transparent",
          opacity,
          rotate: `${spin * (index % 2 === 0 ? 1 : -1) + index * 28}deg`,
          boxShadow: index === 1 ? "0 0 24px rgba(255,18,55,0.34)" : undefined,
        }}
      />
    ))}
  </>
);

const EnergyArcs: React.FC<{opacity: number; phase: number}> = ({opacity, phase}) => (
  <svg
    viewBox="0 0 800 800"
    style={{position: "absolute", inset: 0, opacity, mixBlendMode: "screen"}}
  >
    <defs>
      <filter id="portal-arc-glow" x="-100%" y="-100%" width="300%" height="300%">
        <feGaussianBlur stdDeviation="5" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </defs>
    {Array.from({length: 7}).map((_, index) => {
      const angle = index * 0.92 + phase * Math.PI * 2;
      const innerX = 400 + Math.cos(angle) * 230;
      const innerY = 400 + Math.sin(angle) * 154;
      const outerX = 400 + Math.cos(angle + 0.24) * 390;
      const outerY = 400 + Math.sin(angle + 0.24) * 344;
      const bendX = 400 + Math.cos(angle + 0.6) * 312;
      const bendY = 400 + Math.sin(angle + 0.6) * 254;
      return (
        <path
          key={index}
          d={`M ${innerX} ${innerY} Q ${bendX} ${bendY} ${outerX} ${outerY}`}
          fill="none"
          stroke={index % 3 === 0 ? "#fff" : "#ff2049"}
          strokeWidth={index % 3 === 0 ? 2.6 : 1.4}
          strokeLinecap="round"
          strokeDasharray={`${18 + index * 4} ${38 + index * 7}`}
          strokeDashoffset={-phase * (220 + index * 36)}
          filter="url(#portal-arc-glow)"
        />
      );
    })}
  </svg>
);

export const ToyotaPortalEngine: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;

  const forge = fadeWindow(frame, 4, 22, 66, 91);
  const fracture = fadeWindow(frame, 58, 76, 113, 133);
  const tunnel = fadeWindow(frame, 112, 129, 202, 221);
  const overload = fadeWindow(frame, 194, 213, 252, 270);
  const finalLock = fadeWindow(frame, 248, 268, 290, 299);
  const tunnelTravel = ease(frame, 116, 216);
  const hit = Math.max(0, Math.sin((frame - 205) * 0.29)) * overload;
  const finalPulse = (Math.sin((frame - 257) * 0.19) + 1) / 2;
  const globalFade = Math.min(ease(frame, 0, 8), 1 - ease(frame, 294, 299));

  return (
    <Stage>
      <AbsoluteFill
        style={{
          background: `conic-gradient(from ${phase * 80}deg at 50% 50%,#030103,#30000c,#050103,#5c0017,#030103)`,
          opacity: globalFade * 0.54,
          scale: 1.08,
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 80,
          top: 80,
          width: 640,
          height: 640,
          borderRadius: "50%",
          background:
            "radial-gradient(circle,rgba(255,36,69,0.22),rgba(255,8,47,0.07) 38%,transparent 68%)",
          opacity: Math.max(forge, overload, finalLock),
          scale: 0.92 + Math.sin(phase * Math.PI * 8) * 0.025,
          filter: "blur(8px)",
        }}
      />

      <CoreRings
        opacity={Math.max(forge * 0.55, overload * 0.9, finalLock * 0.38)}
        spin={frame * 0.52}
      />

      <LogoMask
        size={938}
        fill="linear-gradient(145deg,#330008 0%,#ff143b 26%,#fff 45%,#ff2148 52%,#5c0017 78%,#170005 100%)"
        opacity={forge}
        scale={interpolate(frame, [0, 29, 76], [1.38, 1, 1.035], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        })}
        filter={`drop-shadow(0 0 ${14 + forge * 22}px rgba(255,23,59,0.88)) drop-shadow(0 18px 26px rgba(0,0,0,0.9))`}
      />

      <LogoMask
        size={938}
        fill="linear-gradient(110deg,transparent 34%,rgba(255,255,255,0.98) 48%,transparent 61%)"
        opacity={forge * 0.92}
        x={interpolate(frame, [12, 70], [-520, 520], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.45, 0, 0.55, 1),
        })}
        filter="drop-shadow(0 0 20px #fff)"
        mixBlendMode="screen"
      />

      {Array.from({length: 9}).map((_, index) => {
        const start = index * (100 / 9);
        const end = (index + 1) * (100 / 9);
        const kick = Math.sin(frame * 0.45 + index * 1.7);
        return (
          <LogoMask
            key={index}
            size={946}
            fill={
              index % 3 === 0
                ? "linear-gradient(90deg,#fff,#ff244c)"
                : "linear-gradient(90deg,#5d0018,#ff1741,#2d000b)"
            }
            opacity={fracture * (0.7 + (index % 3) * 0.14)}
            x={kick * (8 + (index % 4) * 5) * fracture}
            y={(index - 4) * 2.4 * fracture}
            rotate={kick * 0.45 * fracture}
            clipPath={`inset(${start}% 0 ${100 - end}% 0)`}
            filter="drop-shadow(0 0 16px rgba(255,27,63,0.78))"
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: -80,
          top: interpolate(frame, [62, 123], [98, 704], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.45, 0, 0.55, 1),
          }),
          width: 960,
          height: 5,
          background:
            "linear-gradient(90deg,transparent,#ff1742 20%,#fff 50%,#ff1742 80%,transparent)",
          boxShadow: "0 0 14px #fff,0 0 46px #ff123d",
          opacity: fracture,
        }}
      />

      {Array.from({length: 15}).map((_, index) => {
        const p = (index / 15 + tunnelTravel * 1.35) % 1;
        const size = 82 + p * 1280;
        return (
          <LogoMask
            key={index}
            size={size}
            fill={index % 4 === 0 ? "#fff" : "#ff1742"}
            opacity={tunnel * (1 - p) * (0.18 + p * 1.15)}
            rotate={(index % 2 === 0 ? 1 : -1) * (18 - p * 18)}
            x={Math.sin(index * 1.8 + tunnelTravel * 7) * (1 - p) * 45}
            y={Math.cos(index * 1.3 + tunnelTravel * 6) * (1 - p) * 36}
            filter={`drop-shadow(0 0 ${4 + p * 24}px rgba(255,24,61,0.9))`}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 367,
          top: 324,
          width: 66,
          height: 152,
          borderRadius: "50%",
          background: "#fff",
          boxShadow:
            "0 0 24px #fff,0 0 70px #ff3157,0 0 150px rgba(255,0,45,0.9)",
          opacity: tunnel * ease(frame, 151, 205),
          scale: 0.24 + tunnelTravel * 0.9,
          filter: "blur(7px)",
        }}
      />

      <EnergyArcs opacity={overload} phase={phase * 2.4} />

      <LogoMask
        size={972}
        fill="linear-gradient(180deg,#fff 0%,#ffd7de 22%,#ff1742 44%,#b3002d 72%,#41000f 100%)"
        opacity={overload}
        scale={0.82 + overload * 0.18 + hit * 0.035}
        filter={`drop-shadow(0 0 ${24 + hit * 54}px rgba(255,255,255,0.92)) drop-shadow(0 0 ${56 + hit * 80}px rgba(255,10,51,0.96))`}
      />

      {Array.from({length: 36}).map((_, index) => {
        const angle = (index / 36) * Math.PI * 2 + phase * 2;
        const burst = ease(frame, 202 + (index % 5), 248);
        const radius = 150 + burst * (260 + (index % 7) * 21);
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + Math.cos(angle) * radius,
              top: 400 + Math.sin(angle) * radius,
              width: 24 + (index % 6) * 12,
              height: index % 4 === 0 ? 3 : 1,
              borderRadius: 99,
              background: index % 5 === 0 ? "#fff" : "#ff2148",
              boxShadow: "0 0 12px #ff2148",
              opacity: overload * (1 - burst * 0.54),
              rotate: `${(angle * 180) / Math.PI}deg`,
            }}
          />
        );
      })}

      <LogoMask
        size={952}
        fill="linear-gradient(145deg,#7d001d 0%,#ff123d 34%,#ff647e 48%,#d80031 60%,#650017 100%)"
        opacity={finalLock}
        scale={0.94 + finalLock * 0.06 + finalPulse * 0.012}
        filter={`drop-shadow(0 0 ${22 + finalPulse * 18}px rgba(255,17,57,0.96)) drop-shadow(0 24px 30px rgba(0,0,0,0.9))`}
      />

      <AbsoluteFill
        style={{
          background: `rgba(255,255,255,${hit * 0.13})`,
          mixBlendMode: "screen",
        }}
      />

      <AbsoluteFill
        style={{
          opacity: globalFade * 0.14,
          backgroundImage:
            "repeating-linear-gradient(0deg,transparent 0,transparent 4px,rgba(255,255,255,0.08) 5px)",
          pointerEvents: "none",
        }}
      />

      <AbsoluteFill
        style={{
          backgroundColor: "#000",
          opacity: 1 - globalFade,
          pointerEvents: "none",
        }}
      />
    </Stage>
  );
};
