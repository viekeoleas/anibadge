import type {ReactNode} from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const smooth = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

const windowed = (
  frame: number,
  inStart: number,
  inEnd: number,
  outStart: number,
  outEnd: number,
) =>
  Math.min(
    smooth(frame, inStart, inEnd),
    1 - smooth(frame, outStart, outEnd),
  );

const TempleStage: React.FC<{children: ReactNode}> = ({children}) => (
  <AbsoluteFill style={{backgroundColor: "#000"}}>
    <AbsoluteFill
      style={{
        overflow: "hidden",
        borderRadius: "50%",
        background:
          "radial-gradient(circle at 50% 42%,#210208 0%,#090104 42%,#020102 72%,#000 100%)",
      }}
    >
      {children}
      <AbsoluteFill
        style={{
          pointerEvents: "none",
          background:
            "radial-gradient(circle at 50% 50%,transparent 54%,rgba(0,0,0,0.48) 75%,#000 100%)",
        }}
      />
    </AbsoluteFill>
  </AbsoluteFill>
);

const LogoMask: React.FC<{
  size: number;
  fill: string;
  opacity: number;
  scale?: number;
  x?: number;
  y?: number;
  rotate?: number;
  clipPath?: string;
  filter?: string;
}> = ({
  size,
  fill,
  opacity,
  scale = 1,
  x = 0,
  y = 0,
  rotate = 0,
  clipPath,
  filter,
}) => {
  const mask = `url(${staticFile("toyota-logo-transparent.png")})`;
  return (
    <div
      style={{
        position: "absolute",
        left: (800 - size) / 2,
        top: (800 - size) / 2,
        width: size,
        height: size,
        background: fill,
        WebkitMaskImage: mask,
        maskImage: mask,
        WebkitMaskRepeat: "no-repeat",
        maskRepeat: "no-repeat",
        WebkitMaskPosition: "center",
        maskPosition: "center",
        WebkitMaskSize: "contain",
        maskSize: "contain",
        opacity,
        scale,
        translate: `${x}px ${y}px`,
        rotate: `${rotate}deg`,
        clipPath,
        filter,
      }}
    />
  );
};

const Floor: React.FC<{flight: number; opacity: number}> = ({flight, opacity}) => (
  <svg
    viewBox="0 0 800 800"
    style={{position: "absolute", inset: 0, opacity}}
  >
    <defs>
      <linearGradient id="temple-floor-line" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#ff3154" stopOpacity="0" />
        <stop offset="1" stopColor="#ff3154" stopOpacity="0.64" />
      </linearGradient>
    </defs>
    {[-380, -285, -190, -96, 96, 190, 285, 380].map((x) => (
      <line
        key={x}
        x1="400"
        y1="382"
        x2={400 + x}
        y2="800"
        stroke="url(#temple-floor-line)"
        strokeWidth="1.5"
      />
    ))}
    {Array.from({length: 11}).map((_, index) => {
      const p = (index / 11 + flight * 1.12) % 1;
      const y = 390 + p * p * 410;
      return (
        <line
          key={index}
          x1={400 - p * 430}
          y1={y}
          x2={400 + p * 430}
          y2={y}
          stroke="#ff284d"
          strokeWidth={0.7 + p * 1.8}
          opacity={0.08 + p * 0.36}
        />
      );
    })}
  </svg>
);

const FlyingHall: React.FC<{flight: number; opacity: number}> = ({
  flight,
  opacity,
}) => (
  <>
    {Array.from({length: 12}).map((_, index) => {
      const p = (index / 12 + flight * 1.18) % 1;
      const size = 76 + p * 940;
      return (
        <div
          key={index}
          style={{
            position: "absolute",
            left: 400 - size / 2,
            top: 376 - size * 0.43,
            width: size,
            height: size * 0.86,
            borderRadius: "48% 48% 16% 16%",
            border: `${0.8 + p * 2.2}px solid rgba(214,11,48,${0.08 + p * 0.28})`,
            borderBottomColor: "rgba(255,44,78,0.05)",
            boxShadow:
              p > 0.72 ? "inset 0 0 20px rgba(255,26,60,0.12)" : undefined,
            opacity: opacity * (1 - p * 0.42),
          }}
        />
      );
    })}

    {[-1, 1].map((side) => (
      <div
        key={side}
        style={{
          position: "absolute",
          left: side < 0 ? 63 : 697,
          top: 92,
          width: 40,
          height: 574,
          background:
            side < 0
              ? "linear-gradient(90deg,transparent,rgba(104,1,24,0.9),rgba(255,30,65,0.3))"
              : "linear-gradient(90deg,rgba(255,30,65,0.3),rgba(104,1,24,0.9),transparent)",
          clipPath:
            side < 0
              ? "polygon(0 0,100% 10%,100% 90%,0 100%)"
              : "polygon(0 10%,100% 0,100% 100%,0 90%)",
          opacity: opacity * 0.58,
          filter: "drop-shadow(0 0 16px rgba(255,15,52,0.24))",
        }}
      />
    ))}
  </>
);

const TempleOval: React.FC<{
  left: number;
  top: number;
  width: number;
  height: number;
  border: number;
  opacity: number;
  scale: number;
  x: number;
  y: number;
  rotate: number;
}> = ({left, top, width, height, border, opacity, scale, x, y, rotate}) => (
  <div
    style={{
      position: "absolute",
      left,
      top,
      width,
      height,
      boxSizing: "border-box",
      borderRadius: "50%",
      border: `${border}px solid #d20a36`,
      borderTopColor: "#ff3159",
      borderRightColor: "#8b001f",
      borderBottomColor: "#700019",
      opacity,
      scale,
      translate: `${x}px ${y}px`,
      rotate: `${rotate}deg`,
      boxShadow:
        "inset 0 0 18px rgba(255,95,121,0.28),0 24px 30px rgba(0,0,0,0.9),0 0 16px rgba(255,17,55,0.22)",
    }}
  />
);

export const ToyotaPerspectiveTemple: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const flight = smooth(frame, 0, 299);
  const alignment = smooth(frame, 52, 181);
  const logoLock = windowed(frame, 158, 184, 220, 246);
  const passThrough = smooth(frame, 218, 294);
  const fade = Math.min(smooth(frame, 0, 10), 1 - smooth(frame, 292, 299));
  const architectureOpacity = Math.min(
    smooth(frame, 0, 28),
    1 - smooth(frame, 232, 290),
  );
  const logoSize = 970;

  return (
    <TempleStage>
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 50% 46%,rgba(255,24,59,${0.06 + logoLock * 0.18}) 0%,transparent 48%)`,
          opacity: fade,
        }}
      />

      <Floor flight={flight} opacity={architectureOpacity * 0.72} />
      <FlyingHall flight={flight} opacity={architectureOpacity} />

      <div
        style={{
          position: "absolute",
          left: 175,
          top: 252,
          width: 450,
          height: 260,
          borderRadius: "50%",
          background: "rgba(255,10,48,0.18)",
          filter: "blur(48px)",
          opacity: logoLock,
          scale: 0.74 + logoLock * 0.34,
        }}
      />

      {[
        {
          left: 13,
          top: 150,
          width: 774,
          height: 500,
          border: 54,
          preScale: 1.22,
          preX: -176,
          preY: 92,
          preRotate: -17,
        },
        {
          left: 110,
          top: 198,
          width: 580,
          height: 230,
          border: 52,
          preScale: 0.72,
          preX: 184,
          preY: -156,
          preRotate: 24,
        },
        {
          left: 305,
          top: 182,
          width: 190,
          height: 470,
          border: 44,
          preScale: 1.32,
          preX: 116,
          preY: 154,
          preRotate: -26,
        },
      ].map((oval, index) => (
        <TempleOval
          key={index}
          left={oval.left}
          top={oval.top}
          width={oval.width}
          height={oval.height}
          border={oval.border}
          opacity={architectureOpacity * (1 - logoLock * 0.82) * (1 - passThrough)}
          scale={oval.preScale + (1 - oval.preScale) * alignment}
          x={oval.preX * (1 - alignment)}
          y={oval.preY * (1 - alignment)}
          rotate={oval.preRotate * (1 - alignment)}
        />
      ))}

      <div
        style={{
          position: "absolute",
          left: 60,
          right: 60,
          top: 399,
          height: 2,
          background:
            "linear-gradient(90deg,transparent,rgba(255,38,70,0.4),#fff,rgba(255,38,70,0.4),transparent)",
          boxShadow: "0 0 18px #fff,0 0 52px #ff1742",
          opacity: logoLock * (1 - passThrough),
          scale: 0.5 + logoLock * 0.5,
        }}
      />

      <LogoMask
        size={logoSize}
        fill="linear-gradient(145deg,#79001c 0%,#f20b3b 28%,#ff7389 47%,#e00035 62%,#650017 100%)"
        opacity={logoLock}
        scale={1 + passThrough * 3.6}
        filter={`drop-shadow(0 0 ${18 + logoLock * 24}px rgba(255,21,59,0.92)) drop-shadow(0 26px 34px rgba(0,0,0,0.94))`}
      />

      <LogoMask
        size={logoSize}
        fill={`linear-gradient(105deg,transparent ${20 + phase * 22}%,rgba(255,255,255,0.94) ${38 + phase * 22}%,transparent ${52 + phase * 22}%)`}
        opacity={logoLock * (1 - passThrough)}
        filter="drop-shadow(0 0 18px rgba(255,255,255,0.8))"
      />

      <div
        style={{
          position: "absolute",
          left: 400 - (42 + passThrough * 480) / 2,
          top: 400 - (104 + passThrough * 880) / 2,
          width: 42 + passThrough * 480,
          height: 104 + passThrough * 880,
          borderRadius: "50%",
          background:
            "radial-gradient(ellipse at center,rgba(255,24,58,0.34) 0%,rgba(78,0,18,0.18) 24%,#000 68%)",
          boxShadow: `0 0 ${18 + passThrough * 58}px rgba(255,20,57,${0.68 * (1 - passThrough)})`,
          opacity: passThrough,
        }}
      />

      <AbsoluteFill
        style={{
          opacity: fade * 0.1,
          backgroundImage:
            "repeating-linear-gradient(0deg,transparent 0,transparent 5px,rgba(255,255,255,0.06) 6px)",
          pointerEvents: "none",
        }}
      />

      <AbsoluteFill
        style={{
          backgroundColor: "#000",
          opacity: 1 - fade,
          pointerEvents: "none",
        }}
      />
    </TempleStage>
  );
};
