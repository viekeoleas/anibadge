import type {ReactNode} from "react";
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

const segment = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

const pulse = (
  frame: number,
  start: number,
  peakIn: number,
  peakOut: number,
  end: number,
) => Math.min(segment(frame, start, peakIn), 1 - segment(frame, peakOut, end));

const Stage: React.FC<{children: ReactNode; background: string}> = ({
  children,
  background,
}) => (
  <AbsoluteFill style={{backgroundColor: "#000"}}>
    <AbsoluteFill style={{borderRadius: "50%", overflow: "hidden", background}}>
      {children}
      <AbsoluteFill
        style={{
          pointerEvents: "none",
          background:
            "radial-gradient(circle at 50% 48%,transparent 52%,rgba(0,0,0,0.36) 75%,#000 100%)",
        }}
      />
    </AbsoluteFill>
  </AbsoluteFill>
);

const AccurateToyotaMark: React.FC<{
  opacity: number;
  size: number;
  top: number;
  scale?: number;
  filter?: string;
}> = ({opacity, size, top, scale = 1, filter = ""}) => (
  <Img
    src={staticFile("toyota-logo-transparent.png")}
    style={{
      position: "absolute",
      left: (SIZE - size) / 2,
      top,
      width: size,
      height: size,
      opacity,
      scale,
      filter,
    }}
  />
);

type CelicaSideProps = {
  opacity: number;
  outline: number;
  paint: number;
  assemble?: number;
  x?: number;
  y?: number;
  scale?: number;
  wheelRotation?: number;
  color?: string;
  glow?: boolean;
};

const CelicaSide: React.FC<CelicaSideProps> = ({
  opacity,
  outline,
  paint,
  assemble = 1,
  x = 0,
  y = 230,
  scale = 1,
  wheelRotation = 0,
  color = "#d5122c",
  glow = false,
}) => {
  const explode = 1 - assemble;
  return (
    <svg
      viewBox="0 0 800 400"
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: 800,
        height: 400,
        opacity,
        scale,
        filter: glow ? "drop-shadow(0 0 18px rgba(255,36,64,0.48))" : undefined,
      }}
    >
      <defs>
        <linearGradient id="celica-paint" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ff6374" />
          <stop offset="0.28" stopColor={color} />
          <stop offset="0.7" stopColor="#850919" />
          <stop offset="1" stopColor="#31020a" />
        </linearGradient>
        <linearGradient id="celica-glass" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#bcefff" stopOpacity="0.78" />
          <stop offset="0.38" stopColor="#183342" stopOpacity="0.94" />
          <stop offset="1" stopColor="#050a10" />
        </linearGradient>
        <radialGradient id="celica-wheel" cx="50%" cy="50%" r="50%">
          <stop offset="0" stopColor="#d7e0e6" />
          <stop offset="0.13" stopColor="#3c4650" />
          <stop offset="0.34" stopColor="#aeb7be" />
          <stop offset="0.39" stopColor="#171a1e" />
          <stop offset="0.72" stopColor="#08090b" />
          <stop offset="1" stopColor="#020203" />
        </radialGradient>
        <clipPath id="celica-paint-reveal">
          <rect x="0" y="0" width={800 * paint} height="400" />
        </clipPath>
        <filter id="celica-headlight" x="-100%" y="-100%" width="300%" height="300%">
          <feGaussianBlur stdDeviation="5" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      <g clipPath="url(#celica-paint-reveal)">
        <path
          d="M74 310 C84 278 126 253 205 240 L287 158 C332 119 402 104 478 116 C535 125 580 161 630 218 L707 235 C744 243 765 266 771 292 L746 320 L680 327 C672 278 637 250 591 250 C540 250 506 284 499 329 L302 329 C294 282 258 254 212 254 C164 254 130 286 123 329 L78 320Z"
          fill="url(#celica-paint)"
          transform={`translate(0 ${-explode * 66})`}
        />
        <path
          d="M81 300 C143 288 207 286 285 293 L496 294 C552 269 622 259 756 276 L771 292 L746 320 L680 327 C672 278 637 250 591 250 C540 250 506 284 499 329 L302 329 C294 282 258 254 212 254 C164 254 130 286 123 329 L78 320Z"
          fill="rgba(57,2,10,0.56)"
          transform={`translate(0 ${explode * 38})`}
        />
        <path
          d="M291 163 C335 128 400 117 471 127 C519 134 558 166 603 218 L470 213 L317 211Z"
          fill="url(#celica-glass)"
          stroke="rgba(210,242,255,0.6)"
          strokeWidth="3"
          transform={`translate(0 ${-explode * 112})`}
        />
        <path
          d="M470 126 L468 215"
          fill="none"
          stroke="rgba(227,242,247,0.45)"
          strokeWidth="5"
          transform={`translate(${explode * 38} ${-explode * 112})`}
        />
        <path
          d="M616 217 L686 232 L756 270 L672 264Z"
          fill="#eefaff"
          stroke="#74dfff"
          strokeWidth="3"
          opacity="0.92"
          filter="url(#celica-headlight)"
          transform={`translate(${explode * 86} ${-explode * 18})`}
        />
        <path
          d="M82 287 L126 265 L154 279 L112 305Z"
          fill="#ff304c"
          opacity="0.84"
          transform={`translate(${-explode * 74} ${-explode * 20})`}
        />
        <path
          d="M93 239 L183 220 L226 223 L224 235 L123 250Z"
          fill={color}
          stroke="#ff6b7b"
          strokeWidth="4"
          transform={`translate(${-explode * 96} ${-explode * 84})`}
        />
        <path
          d="M282 226 L492 225 L515 286 L481 310 L300 306Z"
          fill="rgba(255,255,255,0.055)"
          stroke="rgba(255,174,184,0.46)"
          strokeWidth="2"
        />
        <path
          d="M498 294 L716 283"
          fill="none"
          stroke="rgba(255,210,214,0.66)"
          strokeWidth="3"
        />
      </g>

      {[212, 591].map((cx, index) => (
        <g
          key={cx}
          transform={`translate(0 ${explode * 92}) rotate(${wheelRotation * (index === 0 ? -1 : 1)} ${cx} 322)`}
          opacity={clamp(paint * 1.4)}
        >
          <circle cx={cx} cy="322" r="67" fill="#050506" />
          <circle cx={cx} cy="322" r="52" fill="url(#celica-wheel)" />
          {Array.from({length: 5}).map((_, spoke) => (
            <line
              key={spoke}
              x1={cx}
              y1="322"
              x2={cx + Math.cos((spoke / 5) * Math.PI * 2) * 43}
              y2={322 + Math.sin((spoke / 5) * Math.PI * 2) * 43}
              stroke="#e0e7eb"
              strokeWidth="8"
              strokeLinecap="round"
            />
          ))}
          <circle cx={cx} cy="322" r="11" fill="#d51a31" />
        </g>
      ))}

      <g opacity={outline}>
        <path
          d="M74 310 C84 278 126 253 205 240 L287 158 C332 119 402 104 478 116 C535 125 580 161 630 218 L707 235 C744 243 765 266 771 292 L746 320 L680 327 M499 329 L302 329 M123 329 L78 320Z"
          pathLength="1"
          fill="none"
          stroke="#8feaff"
          strokeWidth="4"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeDasharray="1"
          strokeDashoffset={1 - outline}
        />
        <path
          d="M291 163 C335 128 400 117 471 127 C519 134 558 166 603 218 L470 213 L317 211Z M470 126 L468 215 M282 226 L492 225 L515 286 L481 310 L300 306Z"
          pathLength="1"
          fill="none"
          stroke="#4ecde8"
          strokeWidth="2"
          strokeDasharray="1"
          strokeDashoffset={1 - outline}
        />
      </g>
    </svg>
  );
};

const CelicaFront: React.FC<{
  bodyOpacity: number;
  headlightOpacity: number;
  outline: number;
  scale?: number;
}> = ({bodyOpacity, headlightOpacity, outline, scale = 1}) => (
  <svg
    viewBox="0 0 800 800"
    style={{position: "absolute", inset: 0, width: 800, height: 800, scale}}
  >
    <defs>
      <linearGradient id="front-paint" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#ff536a" />
        <stop offset="0.4" stopColor="#be0b25" />
        <stop offset="1" stopColor="#300109" />
      </linearGradient>
      <linearGradient id="front-glass" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#52758b" />
        <stop offset="0.5" stopColor="#101c26" />
        <stop offset="1" stopColor="#030609" />
      </linearGradient>
      <filter id="front-light-glow" x="-100%" y="-100%" width="300%" height="300%">
        <feGaussianBlur stdDeviation="10" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </defs>

    <g opacity={bodyOpacity}>
      <path
        d="M142 530 C152 448 194 369 270 310 L325 258 C349 239 373 229 400 229 C427 229 451 239 475 258 L530 310 C606 369 648 448 658 530 L628 594 C555 624 479 638 400 638 C321 638 245 624 172 594Z"
        fill="url(#front-paint)"
        stroke="#ff596d"
        strokeWidth="4"
      />
      <path
        d="M282 314 L328 263 C349 244 373 235 400 235 C427 235 451 244 472 263 L518 314 L546 370 L254 370Z"
        fill="url(#front-glass)"
        stroke="#82dff5"
        strokeWidth="3"
      />
      <path d="M400 372 L400 582" stroke="rgba(255,180,188,0.42)" strokeWidth="3" />
      <path d="M232 505 Q400 446 568 505" fill="none" stroke="rgba(255,194,201,0.48)" strokeWidth="4" />
      <path d="M350 386 L450 386 L430 423 L370 423Z" fill="#17080c" stroke="#7a1a28" strokeWidth="4" />
      <path d="M306 553 Q400 526 494 553 L474 606 L326 606Z" fill="#09070a" stroke="#60101b" strokeWidth="5" />
      <circle cx="230" cy="542" r="28" fill="#11151a" stroke="#77dff5" strokeWidth="5" />
      <circle cx="570" cy="542" r="28" fill="#11151a" stroke="#77dff5" strokeWidth="5" />
      <image href={staticFile("toyota-logo-transparent.png")} x="358" y="458" width="84" height="84" />
    </g>

    <g opacity={headlightOpacity} filter="url(#front-light-glow)">
      <path
        d="M160 421 L334 378 L297 452 L168 486Z"
        fill="rgba(202,244,251,0.7)"
        stroke="#54ddff"
        strokeWidth="5"
      />
      <path
        d="M640 421 L466 378 L503 452 L632 486Z"
        fill="rgba(202,244,251,0.7)"
        stroke="#54ddff"
        strokeWidth="5"
      />
      <circle cx="280" cy="427" r="13" fill="#fff" />
      <circle cx="520" cy="427" r="13" fill="#fff" />
      <path d="M186 458 L300 404" stroke="rgba(255,255,255,0.82)" strokeWidth="5" />
      <path d="M614 458 L500 404" stroke="rgba(255,255,255,0.82)" strokeWidth="5" />
    </g>

    <path
      d="M142 530 C152 448 194 369 270 310 L325 258 C349 239 373 229 400 229 C427 229 451 239 475 258 L530 310 C606 369 648 448 658 530 L628 594 C555 624 479 638 400 638 C321 638 245 624 172 594Z"
      pathLength="1"
      fill="none"
      stroke="#46dfff"
      strokeWidth="4"
      strokeDasharray="1"
      strokeDashoffset={1 - outline}
      opacity={outline}
    />
  </svg>
);

const Scanlines: React.FC<{opacity: number}> = ({opacity}) => (
  <AbsoluteFill
    style={{
      opacity,
      pointerEvents: "none",
      backgroundImage:
        "repeating-linear-gradient(0deg,transparent 0,transparent 6px,rgba(180,239,255,0.07) 7px)",
    }}
  />
);

export const ToyotaCelicaNightRun: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const frontBody = pulse(frame, 18, 50, 82, 112);
  const introLights = Math.max(1 - segment(frame, 34, 64), segment(frame, 214, 239));
  const frontOutline = pulse(frame, 8, 36, 86, 112);
  const sideOpacity = pulse(frame, 92, 119, 181, 211);
  const drive = segment(frame, 111, 179);
  const brand = pulse(frame, 174, 196, 215, 234);
  const titleOpacity = pulse(frame, 132, 154, 204, 225);

  return (
    <Stage background="radial-gradient(circle at 50% 45%,#061724 0%,#02070d 50%,#010204 100%)">
      <div
        style={{
          position: "absolute",
          left: 82,
          right: 82,
          top: 398,
          height: 2,
          background: "linear-gradient(90deg,transparent,#38d9ff,transparent)",
          opacity: 0.2 + frontBody * 0.52,
          boxShadow: "0 0 28px rgba(56,217,255,0.56)",
        }}
      />

      {Array.from({length: 18}).map((_, index) => {
        const y =
          ((index * 53 + phase * 910 * (1 + (index % 3))) % 910) - 60;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 70 + ((index * 137) % 660),
              top: y,
              width: index % 5 === 0 ? 3 : 1,
              height: 58 + (index % 6) * 22,
              background:
                index % 4 === 0
                  ? "linear-gradient(transparent,rgba(255,40,70,0.6))"
                  : "linear-gradient(transparent,rgba(87,219,255,0.42))",
              opacity: 0.22 + frontBody * 0.36,
              rotate: "8deg",
            }}
          />
        );
      })}

      <CelicaFront
        bodyOpacity={frontBody}
        headlightOpacity={Math.max(introLights, frontBody)}
        outline={frontOutline}
        scale={0.84 + frontBody * 0.08}
      />

      {Array.from({length: 16}).map((_, index) => {
        const progress = ((index / 16 + drive * 1.8) % 1) * 780;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + (index % 2 === 0 ? -1 : 1) * (90 + progress * 0.52),
              top: 440 + progress * 0.32,
              width: 3 + progress * 0.018,
              height: 24 + progress * 0.22,
              background:
                index % 3 === 0
                  ? "linear-gradient(#ff2948,transparent)"
                  : "linear-gradient(#58dfff,transparent)",
              opacity: sideOpacity * (0.18 + progress / 900),
              rotate: index % 2 === 0 ? "-34deg" : "34deg",
              boxShadow: "0 0 10px currentColor",
            }}
          />
        );
      })}

      <CelicaSide
        opacity={sideOpacity}
        outline={Math.max(0.2, 1 - drive * 0.58)}
        paint={segment(frame, 104, 137)}
        x={interpolate(drive, [0, 1], [-78, 58])}
        y={212 - Math.sin(drive * Math.PI) * 18}
        scale={0.86}
        wheelRotation={drive * 960}
        glow
      />

      <div
        style={{
          position: "absolute",
          left: 116,
          right: 116,
          top: 620,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 10,
          opacity: titleOpacity,
          translate: `0 ${18 - titleOpacity * 18}px`,
        }}
      >
        <div
          style={{
            color: "#f5fbff",
            fontFamily: "Arial, sans-serif",
            fontSize: 62,
            fontWeight: 800,
            letterSpacing: 17,
            textShadow: "0 0 24px rgba(63,216,255,0.62)",
          }}
        >
          CELICA
        </div>
        <div
          style={{
            color: "#ff4864",
            fontFamily: "Arial, sans-serif",
            fontSize: 19,
            fontWeight: 700,
            letterSpacing: 8,
          }}
        >
          T230 · 2003
        </div>
      </div>

      <AccurateToyotaMark
        opacity={brand}
        size={344}
        top={220}
        scale={0.78 + brand * 0.22}
        filter="drop-shadow(0 0 22px rgba(255,35,62,0.86))"
      />

      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `rgba(255,255,255,${Math.max(0, Math.sin((frame - 183) * 0.28)) * brand * 0.08})`,
        }}
      />
      <Scanlines opacity={0.16 + Math.sin(phase * Math.PI * 2) * 0.025} />
    </Stage>
  );
};

export const ToyotaCelicaBlueprint: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const returnToGrid = segment(frame, 211, 239);
  const draft = Math.min(segment(frame, 5, 58), 1 - returnToGrid);
  const assemble = segment(frame, 48, 105);
  const paint = Math.min(segment(frame, 96, 139), 1 - segment(frame, 188, 221));
  const sideOpacity = Math.min(segment(frame, 4, 28), 1 - segment(frame, 142, 171));
  const frontReveal = pulse(frame, 143, 170, 196, 221);
  const logoOpacity = pulse(frame, 189, 208, 220, 238);
  const scanX = interpolate(frame, [94, 146], [102, 698], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.45, 0, 0.55, 1),
  });

  return (
    <Stage background="radial-gradient(circle at 50% 48%,#092946 0%,#06192d 56%,#020812 100%)">
      <AbsoluteFill
        style={{
          opacity: 0.46,
          backgroundImage:
            "linear-gradient(rgba(82,206,255,0.12) 1px,transparent 1px),linear-gradient(90deg,rgba(82,206,255,0.12) 1px,transparent 1px)",
          backgroundSize: "40px 40px",
          backgroundPosition: `${Math.sin(phase * Math.PI * 2) * 4}px ${Math.cos(phase * Math.PI * 2) * 4}px`,
        }}
      />

      {[170, 250, 330].map((radius, index) => (
        <div
          key={radius}
          style={{
            position: "absolute",
            left: 400 - radius,
            top: 400 - radius,
            width: radius * 2,
            height: radius * 2,
            borderRadius: "50%",
            border: `${index === 1 ? 2 : 1}px ${index === 1 ? "dashed" : "solid"} rgba(71,207,255,${0.12 + index * 0.06})`,
            rotate: `${(index % 2 === 0 ? 1 : -1) * phase * 70}deg`,
          }}
        />
      ))}

      <div
        style={{
          position: "absolute",
          left: 160,
          top: 110,
          color: "rgba(116,222,255,0.7)",
          fontFamily: "Consolas, monospace",
          fontSize: 18,
          letterSpacing: 4,
          opacity: draft,
        }}
      >
        T230 / 2003
      </div>

      <CelicaSide
        opacity={sideOpacity}
        outline={draft}
        paint={paint}
        assemble={assemble}
        y={214}
        scale={0.88}
        wheelRotation={paint * 250}
        color="#d81330"
      />

      <div
        style={{
          position: "absolute",
          left: scanX,
          top: 216,
          width: 4,
          height: 355,
          background: "linear-gradient(transparent,#d9fbff,#42dfff,transparent)",
          opacity: pulse(frame, 91, 100, 140, 151),
          boxShadow: "0 0 24px #42dfff",
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 122,
          right: 122,
          top: 598,
          display: "flex",
          justifyContent: "space-between",
          color: "rgba(128,227,255,0.64)",
          fontFamily: "Consolas, monospace",
          fontSize: 15,
          letterSpacing: 3,
          opacity: Math.min(draft, 1 - frontReveal),
        }}
      >
        <span>LOW DRAG BODY</span>
        <span>WHEEL AT EACH CORNER</span>
      </div>

      <CelicaFront
        bodyOpacity={frontReveal * 0.84}
        headlightOpacity={frontReveal}
        outline={frontReveal * 0.72}
        scale={0.83 + frontReveal * 0.06}
      />

      <div
        style={{
          position: "absolute",
          left: 120,
          right: 120,
          top: 630,
          textAlign: "center",
          color: "#e7faff",
          fontFamily: "Arial, sans-serif",
          fontSize: 52,
          fontWeight: 800,
          letterSpacing: 14,
          opacity: frontReveal,
          textShadow: "0 0 22px rgba(76,219,255,0.64)",
        }}
      >
        CELICA
      </div>

      <AccurateToyotaMark
        opacity={logoOpacity}
        size={330}
        top={226}
        scale={0.74 + logoOpacity * 0.26}
        filter="drop-shadow(0 0 22px rgba(255,34,62,0.78))"
      />

      {Array.from({length: 10}).map((_, index) => {
        const scatter = logoOpacity * (1 - returnToGrid);
        const angle = index * 2.399 + phase * Math.PI * 2;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + Math.cos(angle) * (160 + index * 9) - 24,
              top: 400 + Math.sin(angle) * (130 + index * 7) - 1,
              width: 48,
              height: 2,
              backgroundColor: index % 3 === 0 ? "#ff3855" : "#55ddff",
              opacity: scatter * 0.68,
              rotate: `${(angle * 180) / Math.PI}deg`,
              boxShadow: "0 0 10px currentColor",
            }}
          />
        );
      })}

      <Scanlines opacity={0.18} />
    </Stage>
  );
};
