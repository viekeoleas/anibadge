import {
  AbsoluteFill,
  Easing,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const BLUE = "#0878c9";
const LIGHT_BLUE = "#43b9f4";
const SILVER = "#dce4e9";
const SIZE = 800;

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const ease = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], {
    ...clamp,
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

const windowOpacity = (
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
    {
      ...clamp,
      easing: Easing.bezier(0.45, 0, 0.55, 1),
    },
  );

const MetalDefinitions: React.FC<{prefix: string}> = ({prefix}) => (
  <defs>
    <linearGradient id={`${prefix}-silver`} x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stopColor="#56626c" />
      <stop offset="0.16" stopColor="#f7fbfd" />
      <stop offset="0.34" stopColor="#77838c" />
      <stop offset="0.52" stopColor="#ffffff" />
      <stop offset="0.72" stopColor="#65717b" />
      <stop offset="0.9" stopColor="#e6edf1" />
      <stop offset="1" stopColor="#39434b" />
    </linearGradient>
    <radialGradient id={`${prefix}-black`} cx="38%" cy="25%" r="78%">
      <stop offset="0" stopColor="#252b31" />
      <stop offset="0.38" stopColor="#080a0d" />
      <stop offset="0.78" stopColor="#010203" />
      <stop offset="1" stopColor="#000" />
    </radialGradient>
    <linearGradient id={`${prefix}-blue`} x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stopColor="#7bd4ff" />
      <stop offset="0.27" stopColor={LIGHT_BLUE} />
      <stop offset="0.58" stopColor={BLUE} />
      <stop offset="1" stopColor="#03447f" />
    </linearGradient>
    <linearGradient id={`${prefix}-white`} x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stopColor="#ffffff" />
      <stop offset="0.5" stopColor="#edf2f4" />
      <stop offset="1" stopColor="#aab5bc" />
    </linearGradient>
    <filter id={`${prefix}-soft-shadow`} x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="10" result="blur" />
      <feColorMatrix
        in="blur"
        type="matrix"
        values="0 0 0 0 0.03  0 0 0 0 0.31  0 0 0 0 0.54  0 0 0 0.45 0"
      />
      <feMerge>
        <feMergeNode />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>
);

const Roundel: React.FC<{
  frame: number;
  opacity: number;
  loopPhase: number;
}> = ({frame, opacity, loopPhase}) => {
  const opening = frame < 150 ? ease(frame, 34, 68) : 1 - ease(frame, 242, 280);

  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox="0 0 800 800"
      style={{position: "absolute", inset: 0, opacity}}
    >
      <MetalDefinitions prefix="premium-logo" />
      <circle cx="400" cy="400" r="398" fill="url(#premium-logo-silver)" />
      <circle cx="400" cy="400" r="383" fill="url(#premium-logo-black)" />
      <circle cx="400" cy="400" r="246" fill="#101419" stroke="#77838c" strokeWidth="7" />

      <g
        style={{
          opacity: 1 - opening * 0.08,
          transformOrigin: "400px 400px",
          rotate: `${opening * 1.5}deg`,
        }}
      >
        <path d="M400 400V158A242 242 0 0 0 158 400Z" fill="url(#premium-logo-white)" />
        <path d="M400 400V158A242 242 0 0 1 642 400Z" fill="url(#premium-logo-blue)" />
        <path d="M400 400V642A242 242 0 0 1 158 400Z" fill="url(#premium-logo-blue)" />
        <path d="M400 400V642A242 242 0 0 0 642 400Z" fill="url(#premium-logo-white)" />
        <circle cx="400" cy="400" r="242" fill="none" stroke="#11161b" strokeWidth="7" />
        <path d="M158 400H642M400 158V642" stroke="#11161b" strokeWidth="7" />
      </g>

      <g
        fill="#f9fbfc"
        fontFamily="Arial, Helvetica, sans-serif"
        fontSize="94"
        fontWeight="700"
        textAnchor="middle"
        style={{opacity: 1 - opening}}
      >
        <text x="230" y="177" rotate="-38 230 177">
          B
        </text>
        <text x="400" y="116">
          M
        </text>
        <text x="570" y="177" rotate="38 570 177">
          W
        </text>
      </g>

      <circle
        cx="400"
        cy="400"
        r="389"
        fill="none"
        stroke="rgba(255,255,255,0.68)"
        strokeWidth="5"
        strokeLinecap="round"
        strokeDasharray="290 2155"
        strokeDashoffset={-loopPhase * 2445}
        style={{filter: "drop-shadow(0 0 9px rgba(255,255,255,0.42))"}}
      />
      <ellipse
        cx="304"
        cy="84"
        rx="150"
        ry="24"
        fill="rgba(255,255,255,0.13)"
        rotate="-12 304 84"
      />
    </svg>
  );
};

const BladeAssembly: React.FC<{
  frame: number;
  opacity: number;
}> = ({frame, opacity}) => {
  const opening = frame < 150 ? ease(frame, 42, 108) : 1 - ease(frame, 212, 270);
  const rotation = opening * 28;
  const spread = opening * 30;

  const blades = [
    {
      path: "M400 394V157A243 243 0 0 0 157 400L382 400Z",
      fill: "url(#premium-blade-white)",
      dx: -spread,
      dy: -spread,
      rotate: -rotation,
    },
    {
      path: "M406 394V157A243 243 0 0 1 649 400L424 400Z",
      fill: "url(#premium-blade-blue)",
      dx: spread,
      dy: -spread,
      rotate: rotation,
    },
    {
      path: "M394 406V649A243 243 0 0 1 151 400L376 400Z",
      fill: "url(#premium-blade-blue)",
      dx: -spread,
      dy: spread,
      rotate: rotation,
    },
    {
      path: "M406 406V649A243 243 0 0 0 649 400L424 400Z",
      fill: "url(#premium-blade-white)",
      dx: spread,
      dy: spread,
      rotate: -rotation,
    },
  ];

  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox="0 0 800 800"
      style={{position: "absolute", inset: 0, opacity}}
    >
      <MetalDefinitions prefix="premium-blade" />
      <circle cx="400" cy="400" r="398" fill="url(#premium-blade-silver)" />
      <circle cx="400" cy="400" r="383" fill="url(#premium-blade-black)" />
      <circle
        cx="400"
        cy="400"
        r="326"
        fill="none"
        stroke="rgba(225,234,239,0.32)"
        strokeWidth="2"
      />
      {blades.map((blade, index) => (
        <g
          key={index}
          style={{
            translate: `${blade.dx}px ${blade.dy}px`,
            rotate: `${blade.rotate}deg`,
            transformOrigin: "400px 400px",
            filter: "drop-shadow(0 14px 16px rgba(0,0,0,0.62))",
          }}
        >
          <path d={blade.path} fill={blade.fill} stroke="#5e6971" strokeWidth="4" />
          <path
            d={blade.path}
            fill="none"
            stroke="rgba(255,255,255,0.35)"
            strokeWidth="2"
          />
        </g>
      ))}
      <circle
        cx="400"
        cy="400"
        r={28 + opening * 30}
        fill="#020304"
        stroke={SILVER}
        strokeWidth="3"
      />
    </svg>
  );
};

const CarFront: React.FC<{
  frame: number;
  opacity: number;
}> = ({frame, opacity}) => {
  const settle = ease(frame, 92, 126);
  const stretch = ease(frame, 134, 166);

  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox="0 0 800 800"
      style={{
        position: "absolute",
        inset: 0,
        opacity,
        scale: 0.94 + settle * 0.06 + stretch * 0.015,
        translate: `0 ${20 - settle * 20 - stretch * 8}px`,
      }}
    >
      <MetalDefinitions prefix="premium-car" />
      <defs>
        <linearGradient id="premium-car-body" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#38434c" />
          <stop offset="0.22" stopColor="#161b20" />
          <stop offset="0.64" stopColor="#050607" />
          <stop offset="1" stopColor="#000" />
        </linearGradient>
        <linearGradient id="premium-headlight" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#87939b" stopOpacity="0" />
          <stop offset="0.3" stopColor="#eef7fb" />
          <stop offset="0.72" stopColor="#fff" />
          <stop offset="1" stopColor={LIGHT_BLUE} />
        </linearGradient>
      </defs>

      <path
        d="M38 544C67 354 164 236 286 201C350 183 450 183 514 201C636 236 733 354 762 544C681 636 562 681 400 687C238 681 119 636 38 544Z"
        fill="url(#premium-car-body)"
        stroke="#59656e"
        strokeWidth="4"
      />
      <path
        d="M105 399C174 305 260 255 350 240M695 399C626 305 540 255 450 240"
        fill="none"
        stroke="rgba(232,240,244,0.32)"
        strokeWidth="5"
        strokeLinecap="round"
      />
      <path
        d="M82 466C152 403 240 381 335 410C273 469 182 500 83 494"
        fill="#050708"
        stroke="url(#premium-headlight)"
        strokeWidth="15"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M718 466C648 403 560 381 465 410C527 469 618 500 717 494"
        fill="#050708"
        stroke="url(#premium-headlight)"
        strokeWidth="15"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M120 456C183 422 249 414 302 425M680 456C617 422 551 414 498 425"
        fill="none"
        stroke="#fff"
        strokeWidth="7"
        strokeLinecap="round"
      />
      <path
        d="M308 505C309 450 337 421 375 439C392 450 398 477 398 542C398 606 371 636 337 619C316 609 307 567 308 505Z"
        fill="#010203"
        stroke="#83909a"
        strokeWidth="6"
      />
      <path
        d="M492 505C491 450 463 421 425 439C408 450 402 477 402 542C402 606 429 636 463 619C484 609 493 567 492 505Z"
        fill="#010203"
        stroke="#83909a"
        strokeWidth="6"
      />
      {[338, 356, 444, 462].map((x) => (
        <path key={x} d={`M${x} 462V600`} stroke="#343d45" strokeWidth="5" />
      ))}
      <path
        d="M125 574C198 632 294 652 400 654C506 652 602 632 675 574"
        fill="none"
        stroke="rgba(232,240,244,0.2)"
        strokeWidth="5"
      />
      <path
        d="M50 513H750"
        stroke="rgba(255,255,255,0.16)"
        strokeWidth="2"
        strokeDasharray="130 540"
        strokeDashoffset={-frame * 3}
      />
    </svg>
  );
};

const RoadRibbon: React.FC<{
  frame: number;
  opacity: number;
}> = ({frame, opacity}) => {
  const travel = ease(frame, 145, 206);
  const roadPath =
    "M-70 858C138 696 324 716 492 620C670 518 726 367 623 282C543 216 405 253 294 209C192 169 157 82 236-63";

  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox="0 0 800 800"
      style={{position: "absolute", inset: 0, opacity}}
    >
      <defs>
        <linearGradient id="premium-road-white" x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stopColor="#8a969f" />
          <stop offset="0.3" stopColor="#ffffff" />
          <stop offset="0.72" stopColor="#e6eef2" />
          <stop offset="1" stopColor="#657079" />
        </linearGradient>
        <linearGradient id="premium-road-blue" x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stopColor="#034778" />
          <stop offset="0.48" stopColor={BLUE} />
          <stop offset="1" stopColor={LIGHT_BLUE} />
        </linearGradient>
      </defs>
      <path
        d={roadPath}
        fill="none"
        stroke="#020304"
        strokeWidth="112"
        strokeLinecap="round"
      />
      <path
        d={roadPath}
        fill="none"
        stroke="url(#premium-road-blue)"
        strokeWidth="82"
        strokeLinecap="round"
        opacity="0.82"
      />
      <path
        d={roadPath}
        fill="none"
        stroke="url(#premium-road-white)"
        strokeWidth="58"
        strokeLinecap="round"
      />
      <path
        d={roadPath}
        fill="none"
        stroke="rgba(255,255,255,0.92)"
        strokeWidth="11"
        strokeLinecap="round"
        strokeDasharray="170 1110"
        strokeDashoffset={900 - travel * 1120}
      />
      <path
        d={roadPath}
        fill="none"
        stroke="rgba(255,255,255,0.23)"
        strokeWidth="3"
        strokeLinecap="round"
        strokeDasharray="48 34"
        strokeDashoffset={-frame * 2.4}
      />
    </svg>
  );
};

const Aperture: React.FC<{
  frame: number;
  opacity: number;
}> = ({frame, opacity}) => {
  const closing = ease(frame, 203, 258);
  const rotation = 46 - closing * 46;
  const scale = 0.83 + closing * 0.17;

  const panels = [
    {path: "M400 394V150A250 250 0 0 0 150 400L382 400Z", fill: "url(#premium-aperture-white)"},
    {path: "M406 394V150A250 250 0 0 1 650 400L424 400Z", fill: "url(#premium-aperture-blue)"},
    {path: "M394 406V650A250 250 0 0 1 150 400L376 400Z", fill: "url(#premium-aperture-blue)"},
    {path: "M406 406V650A250 250 0 0 0 650 400L424 400Z", fill: "url(#premium-aperture-white)"},
  ];

  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox="0 0 800 800"
      style={{position: "absolute", inset: 0, opacity}}
    >
      <MetalDefinitions prefix="premium-aperture" />
      <circle cx="400" cy="400" r="398" fill="url(#premium-aperture-silver)" />
      <circle cx="400" cy="400" r="383" fill="url(#premium-aperture-black)" />
      <circle
        cx="400"
        cy="400"
        r={330 - closing * 74}
        fill="none"
        stroke="rgba(235,241,244,0.46)"
        strokeWidth="4"
      />
      <g
        style={{
          transformOrigin: "400px 400px",
          rotate: `${rotation}deg`,
          scale,
          filter: "drop-shadow(0 16px 18px rgba(0,0,0,0.7))",
        }}
      >
        {panels.map((panel, index) => (
          <path
            key={index}
            d={panel.path}
            fill={panel.fill}
            stroke="#59646c"
            strokeWidth="4"
          />
        ))}
      </g>
      <circle
        cx="400"
        cy="400"
        r={70 - closing * 42}
        fill="#010203"
        stroke="#cbd4d9"
        strokeWidth="4"
      />
      <path
        d="M56 400A344 344 0 0 1 744 400"
        fill="none"
        stroke="rgba(255,255,255,0.48)"
        strokeWidth="5"
        strokeLinecap="round"
        strokeDasharray="220 860"
        strokeDashoffset={-frame * 4}
      />
    </svg>
  );
};

const StudioReflection: React.FC<{
  loopPhase: number;
  opacity: number;
}> = ({loopPhase, opacity}) => (
  <div
    style={{
      position: "absolute",
      left: 400 + Math.sin(loopPhase * Math.PI * 2) * 520,
      top: 400 + Math.cos(loopPhase * Math.PI * 2) * 520,
      width: 230,
      height: 920,
      translate: "-115px -460px",
      rotate: `${-28 + loopPhase * 360}deg`,
      background:
        "linear-gradient(90deg, transparent, rgba(255,255,255,0.04), rgba(255,255,255,0.18), rgba(255,255,255,0.04), transparent)",
      filter: "blur(12px)",
      mixBlendMode: "screen",
      opacity,
    }}
  />
);

export const BmwPremiumMorph: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const loopPhase = frame / (durationInFrames - 1);

  const logoOpacity =
    frame < 150
      ? interpolate(frame, [0, 38, 72], [1, 1, 0], {
          ...clamp,
          easing: Easing.bezier(0.45, 0, 0.55, 1),
        })
      : interpolate(frame, [238, 278, durationInFrames - 1], [0, 1, 1], {
          ...clamp,
          easing: Easing.bezier(0.45, 0, 0.55, 1),
        });
  const bladeOpacity =
    frame < 150
      ? windowOpacity(frame, 35, 60, 92, 118)
      : windowOpacity(frame, 220, 240, 258, 282);
  const carOpacity = windowOpacity(frame, 88, 112, 142, 166);
  const roadOpacity = windowOpacity(frame, 150, 174, 202, 226);
  const apertureOpacity = windowOpacity(frame, 198, 220, 246, 268);

  return (
    <AbsoluteFill style={{backgroundColor: "#000"}}>
      <AbsoluteFill
        style={{
          borderRadius: "50%",
          overflow: "hidden",
          background:
            "radial-gradient(circle at 50% 46%, #11161b 0%, #050607 35%, #010102 68%, #000 100%)",
        }}
      >
        <Roundel frame={frame} opacity={logoOpacity} loopPhase={loopPhase} />
        <BladeAssembly frame={frame} opacity={bladeOpacity} />
        <CarFront frame={frame} opacity={carOpacity} />
        <RoadRibbon frame={frame} opacity={roadOpacity} />
        <Aperture frame={frame} opacity={apertureOpacity} />
        <StudioReflection loopPhase={loopPhase} opacity={0.7} />
        <AbsoluteFill
          style={{
            pointerEvents: "none",
            background:
              "radial-gradient(circle at 50% 48%, transparent 64%, rgba(0,0,0,0.22) 82%, rgba(0,0,0,0.58) 100%)",
          }}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
