import type {CSSProperties, ReactNode} from "react";
import {
  AbsoluteFill,
  Composition,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {ToyotaEyePortal} from "./ToyotaEye";
import {ToyotaKintsugiCore} from "./ToyotaDreams";
import {ToyotaCelicaBlueprint, ToyotaCelicaNightRun} from "./ToyotaCelica";
import {ToyotaCelicaLaserResurrection} from "./ToyotaCelicaLaser";
import {ToyotaPortalEngine} from "./ToyotaPortalEngine";
import {ToyotaPerspectiveTemple} from "./ToyotaPerspectiveTemple";
import {BmwJoyShift, BmwMVelocity, BmwOrbit} from "./BmwShowcase";
import {BmwPremiumMorph} from "./BmwPremiumMorph";
import {ToyotaWheelMorph} from "./ToyotaWheelMorph";

export const CANVAS_SIZE = 800;
export const FPS = 30;
export const DURATION_IN_FRAMES = FPS * 6;

type BadgeFrameProps = {
  children: ReactNode;
  background: string;
};

const BadgeFrame: React.FC<BadgeFrameProps> = ({children, background}) => {
  return (
    <AbsoluteFill style={{backgroundColor: "#000", fontFamily: "Arial, sans-serif"}}>
      <AbsoluteFill
        style={{
          background,
          borderRadius: "50%",
          overflow: "hidden",
        }}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const ToyotaLogo: React.FC<{
  size: number;
  top: number;
  opacity?: number;
  scale?: number;
  glow: string;
}> = ({size, top, opacity = 1, scale = 1, glow}) => {
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: (CANVAS_SIZE - size) / 2,
          top,
          width: size,
          height: size,
          borderRadius: "50%",
          background: `radial-gradient(ellipse at center, ${glow} 0%, transparent 66%)`,
          opacity: 0.34,
          scale: scale * 0.92,
          filter: "blur(22px)",
        }}
      />
      <Img
        src={staticFile("toyota-logo.png")}
        style={{
          position: "absolute",
          left: (CANVAS_SIZE - size) / 2,
          top,
          width: size,
          height: size,
          mixBlendMode: "screen",
          opacity,
          scale,
          filter: "saturate(1.18) brightness(1.08)",
        }}
      />
    </>
  );
};

const EdgeVignette: React.FC<{color: string}> = ({color}) => {
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at 50% 48%, transparent 47%, ${color} 77%, #000 100%)`,
      }}
    />
  );
};

const FineScanlines: React.FC<{opacity: number}> = ({opacity}) => {
  return (
    <AbsoluteFill
      style={{
        opacity,
        backgroundImage:
          "repeating-linear-gradient(0deg, transparent 0px, transparent 5px, rgba(255,255,255,0.08) 6px)",
      }}
    />
  );
};

const Label: React.FC<{
  top: number;
  children: ReactNode;
  color: string;
  fontSize: number;
  letterSpacing: number;
  opacity?: number;
  glow?: string;
  weight?: number;
}> = ({
  top,
  children,
  color,
  fontSize,
  letterSpacing,
  opacity = 1,
  glow = "transparent",
  weight = 700,
}) => {
  return (
    <div
      style={{
        position: "absolute",
        top,
        left: 76,
        right: 76,
        color,
        fontSize,
        fontWeight: weight,
        letterSpacing,
        lineHeight: 1,
        opacity,
        textAlign: "center",
        textShadow: `0 0 22px ${glow}`,
        whiteSpace: "nowrap",
      }}
    >
      {children}
    </div>
  );
};

const ringStyle = (
  size: number,
  color: string,
  opacity: number,
  rotate: number,
): CSSProperties => ({
  position: "absolute",
  left: (CANVAS_SIZE - size) / 2,
  top: (CANVAS_SIZE - size) / 2,
  width: size,
  height: size,
  borderRadius: "50%",
  border: `2px solid ${color}`,
  borderTopColor: "transparent",
  borderBottomColor: "transparent",
  opacity,
  rotate: `${rotate}deg`,
  boxShadow: `0 0 18px ${color}`,
});

export const ToyotaPulse: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const wave = (Math.sin(phase * Math.PI * 2) + 1) / 2;
  const breathe = 0.97 + wave * 0.035;
  const flare = Math.max(0, Math.sin(phase * Math.PI * 4));

  return (
    <BadgeFrame
      background={`radial-gradient(circle at 50% 43%, rgba(225, 0, 34, ${0.22 + wave * 0.13}) 0%, #120107 42%, #030204 73%, #000 100%)`}
    >
      <div
        style={{
          position: "absolute",
          left: 400,
          top: 375,
          width: 1,
          height: 1,
          rotate: `${phase * 360}deg`,
        }}
      >
        {Array.from({length: 18}).map((_, index) => (
          <div
            key={index}
            style={{
              position: "absolute",
              left: -1,
              top: -360,
              width: index % 3 === 0 ? 3 : 1,
              height: 360,
              background:
                "linear-gradient(180deg, transparent, rgba(232, 0, 38, 0.08) 56%, rgba(255, 54, 79, 0.36))",
              opacity: 0.45 + 0.35 * Math.sin(phase * Math.PI * 2 + index),
              rotate: `${index * 20}deg`,
              transformOrigin: "50% 100%",
            }}
          />
        ))}
      </div>

      {[626, 554, 478].map((size, index) => (
        <div
          key={size}
          style={ringStyle(
            size,
            index === 1 ? "rgba(255,255,255,0.38)" : "rgba(229,0,38,0.64)",
            0.22 + index * 0.1,
            (index % 2 === 0 ? 1 : -1) * (phase * 180 + index * 34),
          )}
        />
      ))}

      {Array.from({length: 7}).map((_, index) => {
        const angle = phase * Math.PI * 2 + (index * Math.PI * 2) / 7;
        const radius = 286 + Math.sin(angle * 2) * 12;
        const size = index % 2 === 0 ? 8 : 5;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + Math.cos(angle) * radius - size / 2,
              top: 382 + Math.sin(angle) * radius - size / 2,
              width: size,
              height: size,
              borderRadius: "50%",
              backgroundColor: index === 0 ? "#fff" : "#e50026",
              boxShadow: "0 0 20px #ff1744",
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 186,
          top: 142,
          width: 428,
          height: 428,
          borderRadius: "50%",
          background: `radial-gradient(circle, rgba(255,255,255,${0.03 + flare * 0.08}) 0%, rgba(229,0,38,${0.1 + wave * 0.08}) 38%, transparent 70%)`,
          scale: 0.94 + wave * 0.11,
          filter: "blur(8px)",
        }}
      />

      <ToyotaLogo
        size={430}
        top={145}
        scale={breathe}
        glow={`rgba(255, 0, 48, ${0.45 + wave * 0.35})`}
      />

      <div
        style={{
          position: "absolute",
          left: interpolate(frame, [0, durationInFrames], [-420, 910], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.45, 0, 0.55, 1),
          }),
          top: 168,
          width: 120,
          height: 390,
          rotate: "16deg",
          background:
            "linear-gradient(90deg, transparent, rgba(255,255,255,0.34), transparent)",
          filter: "blur(8px)",
          mixBlendMode: "screen",
        }}
      />

      <Label
        top={586}
        color="#ffffff"
        fontSize={70}
        letterSpacing={18}
        glow="rgba(255,0,48,0.52)"
      >
        TOYOTA
      </Label>
      <Label
        top={668}
        color="#ff5b73"
        fontSize={19}
        letterSpacing={7}
        weight={600}
        opacity={0.72 + wave * 0.22}
      >
        MOTION · PRECISION · DRIVE
      </Label>

      <FineScanlines opacity={0.16} />
      <EdgeVignette color="rgba(18,0,4,0.68)" />
    </BadgeFrame>
  );
};

const CircuitSvg: React.FC<{phase: number; wave: number}> = ({phase, wave}) => {
  return (
    <svg
      width={CANVAS_SIZE}
      height={CANVAS_SIZE}
      viewBox="0 0 800 800"
      style={{position: "absolute", inset: 0}}
    >
      <defs>
        <linearGradient id="road-stroke" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#18dfff" stopOpacity="0.05" />
          <stop offset="1" stopColor="#18dfff" stopOpacity="0.72" />
        </linearGradient>
        <filter id="cyan-glow" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="6" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      {Array.from({length: 8}).map((_, index) => {
        const progress = (index / 8 + phase) % 1;
        const radiusX = 70 + progress * 360;
        const radiusY = 18 + progress * 170;
        return (
          <ellipse
            key={index}
            cx="400"
            cy={360 + progress * 235}
            rx={radiusX}
            ry={radiusY}
            fill="none"
            stroke="url(#road-stroke)"
            strokeWidth={1 + progress * 2.4}
            opacity={0.12 + progress * 0.55}
          />
        );
      })}

      {[-360, -260, -170, -90, 90, 170, 260, 360].map((x, index) => (
        <line
          key={x}
          x1="400"
          y1="360"
          x2={400 + x}
          y2="790"
          stroke="url(#road-stroke)"
          strokeWidth={index === 3 || index === 4 ? 2.5 : 1.2}
          opacity={0.2 + wave * 0.18}
        />
      ))}

      <path
        d="M 314 800 Q 365 540 390 366"
        fill="none"
        stroke="#f21b3f"
        strokeWidth="7"
        strokeLinecap="round"
        strokeDasharray="34 46"
        strokeDashoffset={-phase * 160}
        opacity="0.86"
        filter="url(#cyan-glow)"
      />
      <path
        d="M 486 800 Q 435 540 410 366"
        fill="none"
        stroke="#18dfff"
        strokeWidth="7"
        strokeLinecap="round"
        strokeDasharray="34 46"
        strokeDashoffset={-phase * 160}
        opacity="0.8"
        filter="url(#cyan-glow)"
      />
    </svg>
  );
};

export const ToyotaNightCircuit: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const wave = (Math.sin(phase * Math.PI * 2) + 1) / 2;
  const secondaryWave = (Math.sin(phase * Math.PI * 4 + 0.6) + 1) / 2;

  return (
    <BadgeFrame
      background={`radial-gradient(circle at 50% 43%, rgba(0, 166, 217, ${0.16 + wave * 0.12}) 0%, #03121c 38%, #02060b 72%, #000 100%)`}
    >
      <CircuitSvg phase={phase} wave={wave} />

      {Array.from({length: 3}).map((_, index) => {
        const size = 460 + index * 76;
        return (
          <div
            key={size}
            style={ringStyle(
              size,
              index === 1 ? "rgba(242,27,63,0.54)" : "rgba(24,223,255,0.48)",
              0.18 + index * 0.06,
              (index % 2 === 0 ? 1 : -1) * (phase * 180 + index * 27),
            )}
          />
        );
      })}

      {Array.from({length: 12}).map((_, index) => {
        const angle =
          phase * Math.PI * 2 * (index % 2 === 0 ? 1 : -1) +
          (index * Math.PI * 2) / 12;
        const radius = index % 3 === 0 ? 315 : 272;
        const length = index % 3 === 0 ? 62 : 34;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + Math.cos(angle) * radius - length / 2,
              top: 382 + Math.sin(angle) * radius - 1,
              width: length,
              height: index % 3 === 0 ? 3 : 1,
              borderRadius: 99,
              backgroundColor: index % 4 === 0 ? "#f21b3f" : "#18dfff",
              boxShadow:
                index % 4 === 0 ? "0 0 14px #f21b3f" : "0 0 14px #18dfff",
              opacity: 0.32 + secondaryWave * 0.52,
              rotate: `${(angle * 180) / Math.PI + 90}deg`,
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 198,
          top: 154,
          width: 404,
          height: 404,
          borderRadius: "50%",
          background: `radial-gradient(circle, rgba(24,223,255,${0.08 + wave * 0.06}) 0%, rgba(242,27,63,${0.11 + secondaryWave * 0.05}) 44%, transparent 69%)`,
          scale: 0.94 + wave * 0.08,
          filter: "blur(5px)",
        }}
      />

      <ToyotaLogo
        size={392}
        top={160}
        scale={0.98 + secondaryWave * 0.025}
        glow={`rgba(242, 27, 63, ${0.48 + secondaryWave * 0.32})`}
      />

      <div
        style={{
          position: "absolute",
          left: 306,
          top: 352,
          width: 188,
          height: 2,
          background:
            "linear-gradient(90deg, transparent, #ffffff, #18dfff, transparent)",
          boxShadow: "0 0 20px #18dfff",
          opacity: 0.38 + wave * 0.5,
          scale: 0.7 + wave * 0.36,
        }}
      />

      <Label
        top={98}
        color="#baf7ff"
        fontSize={21}
        letterSpacing={10}
        opacity={0.62 + secondaryWave * 0.28}
        glow="rgba(24,223,255,0.7)"
      >
        NIGHT CIRCUIT
      </Label>
      <Label
        top={586}
        color="#ffffff"
        fontSize={70}
        letterSpacing={18}
        glow="rgba(24,223,255,0.48)"
      >
        TOYOTA
      </Label>
      <Label
        top={668}
        color="#58e9ff"
        fontSize={19}
        letterSpacing={7}
        weight={600}
        opacity={0.7 + wave * 0.22}
      >
        BEYOND THE NEXT TURN
      </Label>

      <FineScanlines opacity={0.21} />
      <EdgeVignette color="rgba(0,5,10,0.72)" />
    </BadgeFrame>
  );
};

export const ToyotaCompositions: React.FC = () => {
  return (
    <>
      <Composition
        id="ToyotaPulseP4"
        component={ToyotaPulse}
        durationInFrames={DURATION_IN_FRAMES}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaNightCircuitP4"
        component={ToyotaNightCircuit}
        durationInFrames={DURATION_IN_FRAMES}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaEyePortalP4"
        component={ToyotaEyePortal}
        durationInFrames={FPS * 8}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaCelicaNightRunP4"
        component={ToyotaCelicaNightRun}
        durationInFrames={FPS * 8}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaKintsugiCoreP4"
        component={ToyotaKintsugiCore}
        durationInFrames={FPS * 8}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaCelicaBlueprintP4"
        component={ToyotaCelicaBlueprint}
        durationInFrames={FPS * 8}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaCelicaLaserResurrectionP4"
        component={ToyotaCelicaLaserResurrection}
        durationInFrames={FPS * 8}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="BmwJoyShiftP4"
        component={BmwJoyShift}
        durationInFrames={FPS * 10}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="BmwMVelocityP4"
        component={BmwMVelocity}
        durationInFrames={FPS * 10}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="BmwOrbitP4"
        component={BmwOrbit}
        durationInFrames={FPS * 10}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaPortalEngineP4"
        component={ToyotaPortalEngine}
        durationInFrames={FPS * 10}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaPerspectiveTempleP4"
        component={ToyotaPerspectiveTemple}
        durationInFrames={FPS * 10}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="BmwPremiumMorphP4"
        component={BmwPremiumMorph}
        durationInFrames={FPS * 10}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
      <Composition
        id="ToyotaWheelMorphP4"
        component={ToyotaWheelMorph}
        durationInFrames={FPS * 10}
        fps={FPS}
        width={CANVAS_SIZE}
        height={CANVAS_SIZE}
      />
    </>
  );
};
