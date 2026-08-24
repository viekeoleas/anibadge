import type {CSSProperties, ReactNode} from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const SIZE = 800;

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const fadeWindow = (
  frame: number,
  fadeInStart: number,
  fadeInEnd: number,
  fadeOutStart: number,
  fadeOutEnd: number,
) =>
  interpolate(
    frame,
    [fadeInStart, fadeInEnd, fadeOutStart, fadeOutEnd],
    [0, 1, 1, 0],
    clamp,
  );

const BadgeCanvas: React.FC<{
  children: ReactNode;
  background: string;
}> = ({children, background}) => (
  <AbsoluteFill style={{backgroundColor: "#000", fontFamily: "Arial, sans-serif"}}>
    <AbsoluteFill
      style={{
        background,
        borderRadius: "50%",
        overflow: "hidden",
      }}
    >
      {children}
      <AbsoluteFill
        style={{
          pointerEvents: "none",
          background:
            "radial-gradient(circle at 50% 48%, transparent 45%, rgba(0,7,18,0.38) 67%, #000 100%)",
        }}
      />
      <AbsoluteFill
        style={{
          pointerEvents: "none",
          opacity: 0.13,
          mixBlendMode: "screen",
          backgroundImage:
            "repeating-linear-gradient(0deg, transparent 0px, transparent 5px, rgba(255,255,255,0.11) 6px)",
        }}
      />
    </AbsoluteFill>
  </AbsoluteFill>
);

const BMW_BLUE = "#1976d2";
const BMW_LIGHT_BLUE = "#28b8ff";
const M_BLUE = "#22a8e0";
const M_NAVY = "#173b78";
const M_RED = "#ef3152";

const BmwRoundel: React.FC<{
  size: number;
  opacity?: number;
  scale?: number;
  rotate?: number;
  style?: CSSProperties;
  glow?: string;
}> = ({
  size,
  opacity = 1,
  scale = 1,
  rotate = 0,
  style,
  glow = "rgba(40,184,255,0.62)",
}) => (
  <div
    style={{
      position: "absolute",
      left: (SIZE - size) / 2,
      top: (SIZE - size) / 2,
      width: size,
      height: size,
      opacity,
      scale,
      rotate: `${rotate}deg`,
      filter: `drop-shadow(0 0 20px ${glow}) drop-shadow(0 16px 30px rgba(0,0,0,0.62))`,
      ...style,
    }}
  >
    <svg width="100%" height="100%" viewBox="0 0 400 400">
      <defs>
        <radialGradient id="bmw-metal" cx="35%" cy="23%" r="78%">
          <stop offset="0" stopColor="#ffffff" />
          <stop offset="0.2" stopColor="#8d9cac" />
          <stop offset="0.47" stopColor="#f8fbff" />
          <stop offset="0.72" stopColor="#4b5967" />
          <stop offset="1" stopColor="#dce5ed" />
        </radialGradient>
        <radialGradient id="bmw-black" cx="38%" cy="25%" r="78%">
          <stop offset="0" stopColor="#263444" />
          <stop offset="0.42" stopColor="#080d13" />
          <stop offset="1" stopColor="#000" />
        </radialGradient>
        <linearGradient id="bmw-blue" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#52c7ff" />
          <stop offset="0.55" stopColor={BMW_BLUE} />
          <stop offset="1" stopColor="#004b9b" />
        </linearGradient>
      </defs>
      <circle cx="200" cy="200" r="191" fill="url(#bmw-metal)" />
      <circle cx="200" cy="200" r="179" fill="url(#bmw-black)" />
      <circle cx="200" cy="200" r="112" fill="#e9f1f7" stroke="#c6d1da" strokeWidth="6" />
      <path d="M200 200V88A112 112 0 0 1 312 200Z" fill="url(#bmw-blue)" />
      <path d="M200 200H88A112 112 0 0 1 200 88Z" fill="#f7fbff" />
      <path d="M200 200v112A112 112 0 0 1 88 200Z" fill="url(#bmw-blue)" />
      <path d="M200 200h112A112 112 0 0 1 200 312Z" fill="#f7fbff" />
      <circle cx="200" cy="200" r="112" fill="none" stroke="#111a22" strokeWidth="6" />
      <text
        x="116"
        y="104"
        fill="#fff"
        fontFamily="Arial, sans-serif"
        fontSize="55"
        fontWeight="800"
        textAnchor="middle"
        rotate="-35 116 104"
      >
        B
      </text>
      <text
        x="200"
        y="75"
        fill="#fff"
        fontFamily="Arial, sans-serif"
        fontSize="55"
        fontWeight="800"
        textAnchor="middle"
      >
        M
      </text>
      <text
        x="284"
        y="104"
        fill="#fff"
        fontFamily="Arial, sans-serif"
        fontSize="55"
        fontWeight="800"
        textAnchor="middle"
        rotate="35 284 104"
      >
        W
      </text>
      <path
        d="M65 228A145 145 0 0 0 335 228"
        fill="none"
        stroke="rgba(255,255,255,0.12)"
        strokeWidth="8"
        strokeLinecap="round"
      />
      <ellipse cx="160" cy="54" rx="80" ry="16" fill="rgba(255,255,255,0.18)" rotate="-12 160 54" />
    </svg>
  </div>
);

const MicroParticles: React.FC<{
  phase: number;
  color?: string;
  count?: number;
  speed?: number;
}> = ({phase, color = BMW_LIGHT_BLUE, count = 24, speed = 1}) => (
  <AbsoluteFill>
    {Array.from({length: count}).map((_, index) => {
      const seed = (index * 47) % 97;
      const angle = (index / count) * Math.PI * 2 + phase * Math.PI * 2 * speed;
      const radius = 150 + ((seed * 7) % 210);
      const dot = 2 + (seed % 5);
      return (
        <div
          key={index}
          style={{
            position: "absolute",
            left: 400 + Math.cos(angle) * radius - dot / 2,
            top: 400 + Math.sin(angle * (index % 2 === 0 ? 1 : -1)) * radius - dot / 2,
            width: dot,
            height: dot,
            borderRadius: "50%",
            background: index % 5 === 0 ? "#fff" : color,
            boxShadow: `0 0 ${8 + dot * 2}px ${color}`,
            opacity: 0.22 + ((seed % 8) / 10),
          }}
        />
      );
    })}
  </AbsoluteFill>
);

const ArcField: React.FC<{
  phase: number;
  opacity?: number;
  colors?: [string, string];
}> = ({phase, opacity = 1, colors = [BMW_LIGHT_BLUE, "#ffffff"]}) => (
  <AbsoluteFill style={{opacity}}>
    {[690, 610, 524, 438].map((size, index) => (
      <div
        key={size}
        style={{
          position: "absolute",
          left: (800 - size) / 2,
          top: (800 - size) / 2,
          width: size,
          height: size,
          borderRadius: "50%",
          border: `${index === 0 ? 1 : 2}px solid ${colors[index % 2]}`,
          borderLeftColor: "transparent",
          borderRightColor: "transparent",
          boxShadow: `0 0 18px ${colors[index % 2]}`,
          opacity: 0.12 + index * 0.08,
          rotate: `${phase * 360 * (index % 2 === 0 ? 1 : -1) + index * 34}deg`,
        }}
      />
    ))}
  </AbsoluteFill>
);

const Caption: React.FC<{
  children: ReactNode;
  top: number;
  opacity: number;
  color?: string;
  size?: number;
  spacing?: number;
}> = ({children, top, opacity, color = "#fff", size = 42, spacing = 10}) => (
  <div
    style={{
      position: "absolute",
      top,
      left: 80,
      right: 80,
      textAlign: "center",
      color,
      fontSize: size,
      fontWeight: 800,
      letterSpacing: spacing,
      lineHeight: 1,
      opacity,
      textShadow: `0 0 24px ${color}`,
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </div>
);

const JoyFace: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => {
  const gaze = Math.sin(((frame - 62) / 42) * Math.PI * 2);
  const bob = Math.sin(((frame - 55) / 54) * Math.PI * 2);
  const leftBlink = interpolate(frame, [111, 115, 120], [28, 2, 28], clamp);
  const rightBlink = interpolate(frame, [132, 136, 141], [28, 2, 28], clamp);

  return (
    <div
      style={{
        position: "absolute",
        left: 190,
        top: 177,
        width: 420,
        height: 420,
        opacity,
        translate: `0 ${bob * 8}px`,
        scale: 0.94 + Math.sin(frame * 0.08) * 0.025,
        borderRadius: "50%",
        background:
          "radial-gradient(circle at 34% 27%, #faffff 0%, #aee9ff 8%, #1887d8 38%, #051c36 72%, #020710 100%)",
        border: "10px solid rgba(220,243,255,0.92)",
        boxShadow:
          "0 0 0 14px rgba(13,29,45,0.9), 0 0 55px rgba(40,184,255,0.68), inset 0 -30px 58px rgba(0,0,0,0.72)",
      }}
    >
      {[128, 267].map((left, index) => {
        const eyeHeight = index === 0 ? leftBlink : rightBlink;
        return (
          <div
            key={left}
            style={{
              position: "absolute",
              left: left - 42,
              top: 137 + (28 - eyeHeight) / 2,
              width: 84,
              height: eyeHeight,
              borderRadius: 99,
              background: "#02070d",
              boxShadow: "0 0 20px rgba(255,255,255,0.25)",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                position: "absolute",
                left: 28 + gaze * 18,
                top: 4,
                width: 18,
                height: 18,
                borderRadius: "50%",
                background: index === 0 ? "#fff" : BMW_LIGHT_BLUE,
                boxShadow: `0 0 14px ${BMW_LIGHT_BLUE}`,
              }}
            />
          </div>
        );
      })}
      <div
        style={{
          position: "absolute",
          left: 98,
          top: 233,
          width: 224,
          height: 104,
          borderBottom: "17px solid #fff",
          borderRadius: "0 0 150px 150px",
          rotate: `${gaze * 2}deg`,
          filter: "drop-shadow(0 0 13px rgba(255,255,255,0.55))",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 30,
          top: 25,
          width: 126,
          height: 34,
          borderRadius: "50%",
          rotate: "-28deg",
          background: "rgba(255,255,255,0.24)",
          filter: "blur(3px)",
        }}
      />
    </div>
  );
};

const SpeedPortal: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => {
  const progress = ((frame - 145) % 60) / 60;
  return (
    <AbsoluteFill style={{opacity}}>
      {Array.from({length: 22}).map((_, index) => {
        const angle = (index / 22) * Math.PI * 2 + frame * 0.007;
        const inner = 100 + ((index * 19 + progress * 210) % 230);
        const length = 80 + (index % 5) * 24;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + Math.cos(angle) * inner,
              top: 400 + Math.sin(angle) * inner,
              width: length,
              height: index % 4 === 0 ? 5 : 2,
              borderRadius: 20,
              background:
                index % 3 === 0
                  ? `linear-gradient(90deg, transparent, ${M_RED})`
                  : `linear-gradient(90deg, transparent, ${BMW_LIGHT_BLUE})`,
              boxShadow: index % 3 === 0 ? `0 0 16px ${M_RED}` : `0 0 16px ${BMW_LIGHT_BLUE}`,
              rotate: `${(angle * 180) / Math.PI}deg`,
              opacity: 0.36 + (index % 4) * 0.15,
            }}
          />
        );
      })}
      <div
        style={{
          position: "absolute",
          left: 283,
          top: 283,
          width: 234,
          height: 234,
          borderRadius: "50%",
          border: "5px solid rgba(255,255,255,0.76)",
          boxShadow: `0 0 26px #fff, 0 0 70px ${BMW_LIGHT_BLUE}, inset 0 0 42px ${M_RED}`,
          scale: 0.92 + Math.sin(frame * 0.16) * 0.08,
        }}
      />
    </AbsoluteFill>
  );
};

export const BmwJoyShift: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const logoOpacity =
    frame < 58
      ? interpolate(frame, [0, 46, 58], [1, 1, 0], clamp)
      : interpolate(frame, [248, durationInFrames - 1], [0, 1], {
          ...clamp,
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        });
  const faceOpacity = fadeWindow(frame, 42, 61, 140, 159);
  const portalOpacity = fadeWindow(frame, 142, 159, 204, 221);
  const joyOpacity = fadeWindow(frame, 202, 219, 246, 262);

  return (
    <BadgeCanvas
      background={`radial-gradient(circle at 50% 44%, rgba(25,118,210,${0.26 + Math.sin(phase * Math.PI * 2) * 0.08}) 0%, #07162b 38%, #020711 72%, #000 100%)`}
    >
      <MicroParticles phase={phase} count={28} />
      <ArcField phase={phase} opacity={0.9} />

      <BmwRoundel
        size={680}
        opacity={logoOpacity}
        scale={0.98 + Math.sin(phase * Math.PI * 2) * 0.025}
        rotate={Math.sin(phase * Math.PI * 2) * 2}
      />

      <JoyFace frame={frame} opacity={faceOpacity} />
      <Caption top={623} opacity={faceOpacity} size={45} spacing={16} color="#ffffff">
        HELLO, ROAD
      </Caption>

      <SpeedPortal frame={frame} opacity={portalOpacity} />
      <Caption top={636} opacity={portalOpacity} size={36} spacing={14} color={BMW_LIGHT_BLUE}>
        FIND YOUR LINE
      </Caption>

      <AbsoluteFill style={{opacity: joyOpacity, alignItems: "center", justifyContent: "center"}}>
        <div
          style={{
            width: 410,
            height: 410,
            borderRadius: "50%",
            background:
              "conic-gradient(from 0deg, #fff 0deg 36deg, #22a8e0 36deg 92deg, #173b78 92deg 150deg, #ef3152 150deg 210deg, #fff 210deg 245deg, #22a8e0 245deg 302deg, #173b78 302deg 335deg, #ef3152 335deg 360deg)",
            rotate: `${(frame - 205) * 1.8}deg`,
            scale: 0.98 + Math.sin(frame * 0.2) * 0.06,
            filter: "drop-shadow(0 0 34px rgba(40,184,255,0.75))",
          }}
        />
        <div
          style={{
            position: "absolute",
            width: 306,
            height: 306,
            borderRadius: "50%",
            background: "radial-gradient(circle, #0b1728 0%, #02060b 74%)",
            boxShadow: "inset 0 0 48px rgba(255,255,255,0.14)",
          }}
        />
        <div
          style={{
            position: "absolute",
            color: "#fff",
            fontSize: 92,
            fontWeight: 900,
            letterSpacing: 16,
            translate: "8px 0",
            textShadow: `0 0 34px ${BMW_LIGHT_BLUE}`,
          }}
        >
          JOY
        </div>
      </AbsoluteFill>
    </BadgeCanvas>
  );
};

const MStripes: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => (
  <AbsoluteFill style={{opacity, alignItems: "center", justifyContent: "center"}}>
    {[
      {color: M_BLUE, x: -120},
      {color: M_NAVY, x: 0},
      {color: M_RED, x: 120},
    ].map(({color, x}, index) => (
      <div
        key={color}
        style={{
          position: "absolute",
          width: 94,
          height: 490,
          borderRadius: 28,
          background: `linear-gradient(180deg, transparent 0%, ${color} 17%, ${color} 82%, transparent 100%)`,
          boxShadow: `0 0 36px ${color}`,
          translate: `${x + interpolate(frame, [34, 78], [-520, 0], {
            ...clamp,
            easing: Easing.bezier(0.12, 0.82, 0.18, 1),
          })}px 0`,
          rotate: "28deg",
          scale: `${1 + index * 0.04} 1`,
        }}
      />
    ))}
  </AbsoluteFill>
);

const HeadlightFace: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => {
  const sweep = Math.sin((frame - 84) * 0.08);
  return (
    <AbsoluteFill style={{opacity}}>
      <svg width="800" height="800" viewBox="0 0 800 800" style={{position: "absolute", inset: 0}}>
        <defs>
          <linearGradient id="car-body" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#233247" />
            <stop offset="0.58" stopColor="#080d15" />
            <stop offset="1" stopColor="#000" />
          </linearGradient>
          <filter id="headlight-glow" x="-80%" y="-80%" width="260%" height="260%">
            <feGaussianBlur stdDeviation="13" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
        <path
          d="M82 525 Q128 313 260 238 Q400 190 540 238 Q672 313 718 525 Q635 620 400 632 Q165 620 82 525Z"
          fill="url(#car-body)"
          stroke="rgba(126,202,255,0.32)"
          strokeWidth="3"
        />
        <path d="M164 438 Q238 374 331 404 Q267 478 160 485Z" fill="#dff9ff" filter="url(#headlight-glow)" />
        <path d="M636 438 Q562 374 469 404 Q533 478 640 485Z" fill="#dff9ff" filter="url(#headlight-glow)" />
        <path d="M178 442 Q242 402 303 416" fill="none" stroke={BMW_LIGHT_BLUE} strokeWidth="12" strokeLinecap="round" />
        <path d="M622 442 Q558 402 497 416" fill="none" stroke={BMW_LIGHT_BLUE} strokeWidth="12" strokeLinecap="round" />
        <ellipse cx="352" cy="512" rx="43" ry="91" fill="#020407" stroke="#6f8498" strokeWidth="5" />
        <ellipse cx="448" cy="512" rx="43" ry="91" fill="#020407" stroke="#6f8498" strokeWidth="5" />
        <path d="M341 450v124M363 450v124M437 450v124M459 450v124" stroke="#263b52" strokeWidth="5" />
        <path d="M176 566 Q400 643 624 566" fill="none" stroke="rgba(255,255,255,0.18)" strokeWidth="4" />
      </svg>
      <div
        style={{
          position: "absolute",
          left: -170 + sweep * 140,
          top: 365,
          width: 1140,
          height: 6,
          rotate: "-4deg",
          background: `linear-gradient(90deg, transparent, ${BMW_LIGHT_BLUE}, #fff, ${BMW_LIGHT_BLUE}, transparent)`,
          boxShadow: `0 0 30px ${BMW_LIGHT_BLUE}`,
          opacity: 0.46,
        }}
      />
    </AbsoluteFill>
  );
};

const RoadRush: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => (
  <AbsoluteFill style={{opacity}}>
    <div
      style={{
        position: "absolute",
        inset: 0,
        background:
          "linear-gradient(152deg, transparent 0 48%, rgba(34,168,224,0.8) 49%, transparent 50%), linear-gradient(208deg, transparent 0 48%, rgba(239,49,82,0.72) 49%, transparent 50%)",
      }}
    />
    {Array.from({length: 9}).map((_, index) => {
      const progress = ((frame * 0.035 + index / 9) % 1);
      return (
        <div
          key={index}
          style={{
            position: "absolute",
            left: 400 - (40 + progress * 360),
            right: 400 - (40 + progress * 360),
            top: 372 + progress * 360,
            height: 2 + progress * 7,
            borderRadius: "50%",
            borderTop: `${2 + progress * 5}px solid ${index % 2 === 0 ? M_BLUE : M_RED}`,
            boxShadow: `0 0 18px ${index % 2 === 0 ? M_BLUE : M_RED}`,
            opacity: 0.2 + progress * 0.72,
          }}
        />
      );
    })}
    <div
      style={{
        position: "absolute",
        left: 393,
        top: 386,
        width: 14,
        height: 370,
        background: "repeating-linear-gradient(180deg, #fff 0 34px, transparent 34px 74px)",
        opacity: 0.7,
        translate: `0 ${((frame * 12) % 74) - 74}px`,
        filter: "drop-shadow(0 0 10px #fff)",
      }}
    />
  </AbsoluteFill>
);

const EnergyCore: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => (
  <AbsoluteFill style={{opacity, alignItems: "center", justifyContent: "center"}}>
    {[500, 410, 320].map((size, index) => (
      <div
        key={size}
        style={{
          position: "absolute",
          width: size,
          height: size,
          borderRadius: "50%",
          border: `${index + 1}px solid ${[M_BLUE, M_NAVY, M_RED][index]}`,
          borderTopColor: "transparent",
          borderBottomColor: "transparent",
          rotate: `${(frame - 198) * (index % 2 === 0 ? 1.7 : -1.2)}deg`,
          boxShadow: `0 0 20px ${[M_BLUE, M_NAVY, M_RED][index]}`,
          opacity: 0.45 + index * 0.16,
        }}
      />
    ))}
    <div
      style={{
        width: 220,
        height: 220,
        borderRadius: "50%",
        background: `radial-gradient(circle, #fff 0%, ${BMW_LIGHT_BLUE} 12%, ${M_NAVY} 42%, #02050a 72%)`,
        boxShadow: `0 0 38px #fff, 0 0 94px ${BMW_LIGHT_BLUE}`,
        scale: 0.94 + Math.max(0, Math.sin((frame - 198) * 0.23)) * 0.13,
      }}
    />
    <div
      style={{
        position: "absolute",
        color: "#fff",
        fontSize: 54,
        fontWeight: 900,
        letterSpacing: 4,
        textShadow: "0 0 18px #fff",
      }}
    >
      M
    </div>
  </AbsoluteFill>
);

export const BmwMVelocity: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const logoOpacity =
    frame < 48
      ? interpolate(frame, [0, 36, 48], [1, 1, 0], clamp)
      : interpolate(frame, [252, durationInFrames - 1], [0, 1], clamp);
  const stripesOpacity = fadeWindow(frame, 34, 47, 84, 99);
  const carOpacity = fadeWindow(frame, 80, 96, 145, 160);
  const roadOpacity = fadeWindow(frame, 140, 156, 204, 220);
  const coreOpacity = fadeWindow(frame, 198, 214, 248, 263);

  return (
    <BadgeCanvas
      background={`radial-gradient(circle at 50% 48%, rgba(20,58,107,${0.34 + Math.sin(phase * Math.PI * 2) * 0.08}) 0%, #07101c 43%, #010307 78%, #000 100%)`}
    >
      <MicroParticles phase={phase} color={M_RED} count={20} speed={-0.7} />
      <ArcField phase={phase} opacity={0.56} colors={[M_BLUE, M_RED]} />

      <BmwRoundel size={680} opacity={logoOpacity} scale={1 + Math.sin(phase * Math.PI * 2) * 0.02} />

      <MStripes frame={frame} opacity={stripesOpacity} />
      <Caption top={629} opacity={stripesOpacity} size={27} spacing={8} color="#eaf8ff">
        THREE COLORS. ONE PULSE.
      </Caption>

      <HeadlightFace frame={frame} opacity={carOpacity} />
      <Caption top={650} opacity={carOpacity} size={29} spacing={9} color={BMW_LIGHT_BLUE}>
        EYES ON THE APEX
      </Caption>

      <RoadRush frame={frame} opacity={roadOpacity} />
      <Caption top={116} opacity={roadOpacity} size={54} spacing={14}>
        FULL SEND
      </Caption>

      <EnergyCore frame={frame} opacity={coreOpacity} />
      <Caption top={642} opacity={coreOpacity} size={28} spacing={8} color={M_RED}>
        POWER HAS A HEARTBEAT
      </Caption>
    </BadgeCanvas>
  );
};

const Planet: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => (
  <AbsoluteFill style={{opacity, alignItems: "center", justifyContent: "center"}}>
    <div
      style={{
        width: 366,
        height: 366,
        borderRadius: "50%",
        background:
          "radial-gradient(circle at 31% 25%, #e8fbff 0%, #77d6ff 8%, #176db6 30%, #071b36 60%, #01040a 78%)",
        boxShadow: `inset -46px -36px 72px #000, 0 0 54px ${BMW_LIGHT_BLUE}`,
        rotate: `${(frame - 52) * 0.45}deg`,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 38,
          top: 72,
          width: 260,
          height: 74,
          borderRadius: "50%",
          borderTop: "14px solid rgba(255,255,255,0.24)",
          rotate: "-14deg",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 88,
          top: 210,
          width: 238,
          height: 72,
          borderRadius: "50%",
          borderBottom: "18px solid rgba(5,36,82,0.9)",
          rotate: "11deg",
        }}
      />
    </div>
    <div
      style={{
        position: "absolute",
        width: 592,
        height: 156,
        borderRadius: "50%",
        border: "5px solid rgba(202,240,255,0.8)",
        borderLeftColor: "transparent",
        borderRightColor: "transparent",
        rotate: `${-14 + Math.sin(frame * 0.05) * 4}deg`,
        boxShadow: `0 0 21px ${BMW_LIGHT_BLUE}`,
      }}
    />
  </AbsoluteFill>
);

const OrbitalSystem: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => (
  <AbsoluteFill style={{opacity}}>
    {[520, 610, 700].map((size, index) => (
      <div
        key={size}
        style={{
          position: "absolute",
          left: (800 - size) / 2,
          top: (800 - size * 0.42) / 2,
          width: size,
          height: size * 0.42,
          borderRadius: "50%",
          border: `2px solid ${index === 1 ? M_RED : BMW_LIGHT_BLUE}`,
          opacity: 0.3 + index * 0.13,
          rotate: `${index % 2 === 0 ? -18 : 18}deg`,
          boxShadow: `0 0 13px ${index === 1 ? M_RED : BMW_LIGHT_BLUE}`,
        }}
      >
        <div
          style={{
            position: "absolute",
            left: `${50 + Math.cos((frame * (0.018 + index * 0.004) + index) * Math.PI) * 48}%`,
            top: `${50 + Math.sin((frame * (0.018 + index * 0.004) + index) * Math.PI) * 46}%`,
            width: 16 + index * 6,
            height: 16 + index * 6,
            borderRadius: "50%",
            background: index === 1 ? M_RED : "#fff",
            boxShadow: `0 0 22px ${index === 1 ? M_RED : BMW_LIGHT_BLUE}`,
          }}
        />
      </div>
    ))}
    <BmwRoundel size={320} opacity={1} scale={0.98 + Math.sin(frame * 0.11) * 0.04} />
  </AbsoluteFill>
);

const FutureCity: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => (
  <AbsoluteFill style={{opacity}}>
    <div
      style={{
        position: "absolute",
        left: 80,
        right: 80,
        bottom: 120,
        height: 320,
        display: "flex",
        alignItems: "flex-end",
        justifyContent: "center",
        gap: 10,
      }}
    >
      {Array.from({length: 17}).map((_, index) => {
        const height = 90 + ((index * 71) % 220);
        return (
          <div
            key={index}
            style={{
              width: 26 + (index % 3) * 8,
              height,
              background:
                "linear-gradient(180deg, rgba(21,72,122,0.94), rgba(2,9,19,0.98))",
              borderTop: `3px solid ${index % 4 === 0 ? M_RED : BMW_LIGHT_BLUE}`,
              boxShadow: `0 0 14px ${index % 4 === 0 ? M_RED : BMW_LIGHT_BLUE}`,
              translate: `0 ${interpolate(frame, [145, 174], [height + 80, 0], {
                ...clamp,
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              })}px`,
            }}
          >
            {Array.from({length: Math.floor(height / 34)}).map((__, lightIndex) => (
              <div
                key={lightIndex}
                style={{
                  margin: "15px auto 0",
                  width: index % 2 === 0 ? 5 : 12,
                  height: 3,
                  background: (index + lightIndex) % 3 === 0 ? M_RED : BMW_LIGHT_BLUE,
                  opacity: 0.35 + (((index * 3 + lightIndex) % 5) / 8),
                }}
              />
            ))}
          </div>
        );
      })}
    </div>
    <div
      style={{
        position: "absolute",
        left: -80,
        right: -80,
        bottom: 92,
        height: 5,
        background: `linear-gradient(90deg, transparent, ${BMW_LIGHT_BLUE}, #fff, ${BMW_LIGHT_BLUE}, transparent)`,
        boxShadow: `0 0 30px ${BMW_LIGHT_BLUE}`,
      }}
    />
  </AbsoluteFill>
);

const HorizonRadar: React.FC<{frame: number; opacity: number}> = ({frame, opacity}) => (
  <AbsoluteFill style={{opacity, alignItems: "center", justifyContent: "center"}}>
    {[520, 390, 260].map((size, index) => (
      <div
        key={size}
        style={{
          position: "absolute",
          width: size,
          height: size,
          borderRadius: "50%",
          border: `2px solid rgba(40,184,255,${0.26 + index * 0.14})`,
          boxShadow: `inset 0 0 22px rgba(40,184,255,0.18)`,
        }}
      />
    ))}
    {Array.from({length: 12}).map((_, index) => (
      <div
        key={index}
        style={{
          position: "absolute",
          width: 540,
          height: 1,
          background: "linear-gradient(90deg, transparent, rgba(40,184,255,0.44), transparent)",
          rotate: `${index * 15}deg`,
        }}
      />
    ))}
    <div
      style={{
        position: "absolute",
        width: 500,
        height: 250,
        borderRadius: "500px 500px 0 0",
        transformOrigin: "50% 100%",
        background: `conic-gradient(from 270deg at 50% 100%, transparent 0deg, transparent 72deg, rgba(40,184,255,0.54) 89deg, transparent 91deg)`,
        rotate: `${(frame - 202) * 3.2}deg`,
        opacity: 0.62,
      }}
    />
    <div
      style={{
        position: "absolute",
        width: 172,
        height: 172,
        borderRadius: "50%",
        background: "radial-gradient(circle, #fff 0%, #23b6ff 10%, #093b70 38%, #01030a 74%)",
        boxShadow: `0 0 48px ${BMW_LIGHT_BLUE}`,
      }}
    />
  </AbsoluteFill>
);

export const BmwOrbit: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const logoOpacity =
    frame < 55
      ? interpolate(frame, [0, 40, 55], [1, 1, 0], clamp)
      : interpolate(frame, [252, durationInFrames - 1], [0, 1], clamp);
  const planetOpacity = fadeWindow(frame, 42, 58, 105, 121);
  const orbitOpacity = fadeWindow(frame, 102, 118, 158, 174);
  const cityOpacity = fadeWindow(frame, 153, 170, 207, 224);
  const radarOpacity = fadeWindow(frame, 202, 219, 249, 264);

  return (
    <BadgeCanvas
      background={`radial-gradient(circle at 50% 45%, rgba(16,82,142,${0.22 + Math.sin(phase * Math.PI * 2) * 0.06}) 0%, #050d1d 42%, #01030a 78%, #000 100%)`}
    >
      <MicroParticles phase={phase} count={34} speed={0.32} />
      <ArcField phase={phase} opacity={0.4} />

      <BmwRoundel size={680} opacity={logoOpacity} scale={0.99 + Math.sin(phase * Math.PI * 2) * 0.02} />

      <Planet frame={frame} opacity={planetOpacity} />
      <Caption top={636} opacity={planetOpacity} size={31} spacing={9} color={BMW_LIGHT_BLUE}>
        A WORLD IN MOTION
      </Caption>

      <OrbitalSystem frame={frame} opacity={orbitOpacity} />
      <Caption top={644} opacity={orbitOpacity} size={28} spacing={8}>
        GRAVITY: OPTIONAL
      </Caption>

      <FutureCity frame={frame} opacity={cityOpacity} />
      <Caption top={120} opacity={cityOpacity} size={31} spacing={9} color="#e9f8ff">
        ARRIVE IN 2035
      </Caption>

      <HorizonRadar frame={frame} opacity={radarOpacity} />
      <Caption top={632} opacity={radarOpacity} size={30} spacing={9} color={BMW_LIGHT_BLUE}>
        NEXT STOP: FUTURE
      </Caption>
    </BadgeCanvas>
  );
};
