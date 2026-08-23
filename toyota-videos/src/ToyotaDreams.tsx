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

const lerp = (from: number, to: number, progress: number) =>
  from + (to - from) * progress;

const smoothPulse = (
  frame: number,
  start: number,
  peakIn: number,
  peakOut: number,
  end: number,
) => Math.min(segment(frame, start, peakIn), 1 - segment(frame, peakOut, end));

const CircleStage: React.FC<{
  children: ReactNode;
  background: string;
}> = ({children, background}) => {
  return (
    <AbsoluteFill style={{backgroundColor: "#000"}}>
      <AbsoluteFill
        style={{
          borderRadius: "50%",
          overflow: "hidden",
          background,
        }}
      >
        {children}
        <AbsoluteFill
          style={{
            pointerEvents: "none",
            background:
              "radial-gradient(circle at 50% 48%, transparent 50%, rgba(0,0,0,0.28) 72%, #000 100%)",
          }}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const FilmTexture: React.FC<{opacity?: number; color?: string}> = ({
  opacity = 0.18,
  color = "255,255,255",
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  return (
    <AbsoluteFill style={{opacity, pointerEvents: "none"}}>
      {Array.from({length: 38}).map((_, index) => {
        const x =
          (index * 149) % 800 +
          Math.sin(phase * Math.PI * 2 + index * 1.91) * (8 + (index % 5) * 3);
        const y =
          (index * 83) % 800 +
          Math.cos(phase * Math.PI * 2 + index * 1.37) * (7 + (index % 4) * 3);
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: x - 10,
              top: y - 10,
              width: index % 7 === 0 ? 3 : 1,
              height: index % 7 === 0 ? 3 : 1,
              borderRadius: "50%",
              backgroundColor: `rgba(${color},${0.28 + (index % 4) * 0.16})`,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

const ToyotaLogo: React.FC<{
  opacity: number;
  scale: number;
  size?: number;
  colorFilter?: string;
  glow?: string;
}> = ({
  opacity,
  scale,
  size = 420,
  colorFilter = "",
  glow = "rgba(255,33,63,0.72)",
}) => (
  <Img
    src={staticFile("toyota-logo-transparent.png")}
    style={{
      position: "absolute",
      left: (SIZE - size) / 2,
      top: (SIZE - size) / 2,
      width: size,
      height: size,
      opacity,
      scale,
      filter: `${colorFilter} drop-shadow(0 0 17px ${glow})`,
    }}
  />
);

// ---------------------------------------------------------------------------
// 1. SAKURA REACTOR: seed -> living bonsai -> petal storm -> Toyota mark -> seed
// ---------------------------------------------------------------------------

const branches = [
  "M400 610 C398 540 389 470 405 394 C418 334 445 286 472 232",
  "M402 486 C350 448 310 394 272 329",
  "M407 420 C468 390 521 342 552 285",
  "M394 535 C350 520 302 482 268 440",
  "M406 354 C374 322 353 283 348 239",
  "M445 315 C500 309 548 286 582 250",
  "M350 447 C306 438 263 407 230 372",
  "M472 333 C518 343 565 336 610 304",
];

const branchEnds = [
  [472, 232],
  [272, 329],
  [552, 285],
  [268, 440],
  [348, 239],
  [582, 250],
  [230, 372],
  [610, 304],
] as const;

const SakuraTree: React.FC<{growth: number; opacity: number}> = ({
  growth,
  opacity,
}) => (
  <svg
    width={SIZE}
    height={SIZE}
    viewBox="0 0 800 800"
    style={{position: "absolute", inset: 0, opacity}}
  >
    <defs>
      <linearGradient id="sakura-trunk" x1="0" y1="1" x2="0.7" y2="0">
        <stop offset="0" stopColor="#2d080c" />
        <stop offset="0.48" stopColor="#8b272b" />
        <stop offset="1" stopColor="#ffd4c5" />
      </linearGradient>
      <filter id="sakura-glow" x="-80%" y="-80%" width="260%" height="260%">
        <feGaussianBlur stdDeviation="5" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </defs>
    {branches.map((path, index) => (
      <path
        key={path}
        d={path}
        pathLength={1}
        fill="none"
        stroke="url(#sakura-trunk)"
        strokeWidth={index === 0 ? 25 : Math.max(5, 14 - index)}
        strokeLinecap="round"
        strokeDasharray="1"
        strokeDashoffset={1 - clamp(growth * 1.35 - index * 0.06)}
        filter="url(#sakura-glow)"
      />
    ))}
  </svg>
);

export const ToyotaSakuraReactor: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const treeGrowth = segment(frame, 8, 78);
  const treeFade = 1 - segment(frame, 112, 148);
  const lift = segment(frame, 88, 137);
  const gather = segment(frame, 132, 177);
  const returnToSeed = segment(frame, 205, 239);
  const logoOpacity = smoothPulse(frame, 142, 169, 202, 232);
  const seedOpacity = Math.max(1 - segment(frame, 0, 30), segment(frame, 218, 239));
  const storyLife = treeGrowth * (1 - returnToSeed);
  const wind = Math.sin(phase * Math.PI * 2);

  return (
    <CircleStage
      background={`radial-gradient(circle at 50% 36%, rgba(255,185,176,${0.11 + storyLife * 0.12}) 0%, #2b070d 30%, #0c070b 66%, #020303 100%)`}
    >
      <div
        style={{
          position: "absolute",
          left: 248,
          top: 116,
          width: 304,
          height: 304,
          borderRadius: "50%",
          background:
            "radial-gradient(circle at 38% 34%, #fff7e5 0%, #ffc5b0 25%, #df313c 72%, rgba(89,4,17,0.2) 100%)",
          opacity: 0.42 + storyLife * 0.35,
          scale: 0.9 + Math.sin(phase * Math.PI * 2) * 0.025,
          boxShadow: "0 0 80px rgba(255,87,91,0.28)",
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 120,
          right: 120,
          top: 612,
          height: 2,
          background:
            "linear-gradient(90deg, transparent, rgba(255,220,205,0.54), transparent)",
          boxShadow: "0 0 30px rgba(255,70,82,0.38)",
        }}
      />

      <SakuraTree growth={treeGrowth} opacity={treeFade} />

      {Array.from({length: 42}).map((_, index) => {
        const branch = branchEnds[index % branchEnds.length];
        const sourceX = branch[0] + Math.sin(index * 4.17) * (24 + (index % 4) * 8);
        const sourceY = branch[1] + Math.cos(index * 2.31) * (20 + (index % 5) * 7);
        const swirlAngle = index * 2.399 + lift * Math.PI * (2.2 + (index % 3) * 0.35);
        const swirlRadius = 108 + (index % 8) * 27;
        const stormX = 400 + Math.cos(swirlAngle) * swirlRadius;
        const stormY = 398 + Math.sin(swirlAngle) * swirlRadius * 0.68 - lift * 34;
        const targetAngle = index * 2.399;
        const targetX = 400 + Math.cos(targetAngle) * (104 + (index % 4) * 34);
        const targetY = 400 + Math.sin(targetAngle) * (58 + (index % 3) * 31);
        const liftedX = lerp(sourceX, stormX, lift);
        const liftedY = lerp(sourceY, stormY, lift);
        const gatheredX = lerp(liftedX, targetX, gather);
        const gatheredY = lerp(liftedY, targetY, gather);
        const x = lerp(gatheredX, 400, returnToSeed);
        const y = lerp(gatheredY, 607, returnToSeed);
        const bloom = segment(frame, 34 + (index % 9) * 3, 66 + (index % 9) * 3);
        const petalOpacity = Math.min(bloom, 1 - returnToSeed);
        const petalSize = 8 + (index % 5) * 3;

        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: x - petalSize / 2,
              top: y - petalSize / 2,
              width: petalSize,
              height: petalSize * 1.55,
              borderRadius: "90% 12% 82% 22%",
              background:
                index % 5 === 0
                  ? "linear-gradient(145deg,#fff8ec,#ff9a9f 60%,#c81936)"
                  : "linear-gradient(145deg,#ffd4d0,#ff6177 65%,#9c0b28)",
              opacity: petalOpacity,
              rotate: `${index * 41 + frame * (1.4 + (index % 3) * 0.45)}deg`,
              scale: bloom * (1 - returnToSeed * 0.72),
              boxShadow: index % 6 === 0 ? "0 0 13px rgba(255,166,170,0.65)" : "none",
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 359,
          top: 566,
          width: 82,
          height: 82,
          borderRadius: "56% 44% 55% 45%",
          background:
            "radial-gradient(circle at 36% 30%, #fff1cf 0%, #ff4860 24%, #7d061f 70%, #190109 100%)",
          opacity: seedOpacity,
          scale: 0.45 + seedOpacity * 0.55,
          rotate: `${wind * 5}deg`,
          boxShadow: `0 0 ${18 + seedOpacity * 34}px rgba(255,52,76,0.72)`,
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 198,
          top: 198,
          width: 404,
          height: 404,
          borderRadius: "50%",
          background:
            "radial-gradient(circle, rgba(255,219,194,0.2), rgba(255,38,68,0.11) 42%, transparent 70%)",
          opacity: logoOpacity,
          scale: 0.78 + logoOpacity * 0.3,
          filter: "blur(10px)",
        }}
      />
      <ToyotaLogo
        opacity={logoOpacity}
        scale={0.78 + logoOpacity * 0.22}
        glow="rgba(255,105,112,0.88)"
      />

      <FilmTexture opacity={0.2} color="255,205,195" />
    </CircleStage>
  );
};

// ---------------------------------------------------------------------------
// 2. KINTSUGI CORE: ceramic planet -> golden fracture -> reactor -> restoration
// ---------------------------------------------------------------------------

const crackPaths = [
  "M401 188 L372 272 L411 326 L377 401 L421 462 L394 614",
  "M375 276 L301 251 L262 204",
  "M410 325 L490 286 L548 226",
  "M378 400 L301 437 L249 514",
  "M422 462 L496 503 L552 579",
  "M304 437 L269 390 L215 372",
  "M492 286 L535 337 L594 353",
];

const KintsugiCracks: React.FC<{progress: number; opacity: number}> = ({
  progress,
  opacity,
}) => (
  <svg
    width={SIZE}
    height={SIZE}
    viewBox="0 0 800 800"
    style={{position: "absolute", inset: 0, opacity}}
  >
    <defs>
      <filter id="gold-glow" x="-80%" y="-80%" width="260%" height="260%">
        <feGaussianBlur stdDeviation="4" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </defs>
    {crackPaths.map((path, index) => (
      <path
        key={path}
        d={path}
        pathLength={1}
        fill="none"
        stroke={index % 2 === 0 ? "#fff0a8" : "#f0ad27"}
        strokeWidth={index === 0 ? 7 : 4}
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeDasharray="1"
        strokeDashoffset={1 - clamp(progress * 1.25 - index * 0.055)}
        filter="url(#gold-glow)"
      />
    ))}
  </svg>
);

export const ToyotaKintsugiCore: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const crack = Math.min(segment(frame, 10, 78), 1 - segment(frame, 214, 239));
  const open = Math.min(segment(frame, 72, 112), 1 - segment(frame, 187, 229));
  const core = smoothPulse(frame, 88, 120, 190, 226);
  const logoOpacity = smoothPulse(frame, 122, 151, 188, 216);
  const ignition = smoothPulse(frame, 100, 126, 166, 194);
  const sphereRotate = Math.sin(phase * Math.PI * 2) * 7;

  return (
    <CircleStage background="radial-gradient(circle at 50% 46%, #191510 0%, #080707 54%, #010202 100%)">
      <div
        style={{
          position: "absolute",
          left: 118,
          top: 118,
          width: 564,
          height: 564,
          borderRadius: "50%",
          border: "1px solid rgba(233,184,76,0.22)",
          boxShadow: "inset 0 0 80px rgba(0,0,0,0.88), 0 0 70px rgba(224,155,37,0.12)",
          rotate: `${sphereRotate}deg`,
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 181,
          top: 181,
          width: 438,
          height: 438,
          borderRadius: "50%",
          background:
            "radial-gradient(circle at 34% 27%, #554b42 0%, #201b19 29%, #09090a 72%, #020303 100%)",
          opacity: 1 - open * 0.88,
          boxShadow:
            "inset -42px -52px 76px rgba(0,0,0,0.92), inset 18px 16px 30px rgba(255,233,193,0.08), 0 32px 58px rgba(0,0,0,0.72)",
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 248,
          top: 248,
          width: 304,
          height: 304,
          borderRadius: "50%",
          background:
            "radial-gradient(circle, #fff7c9 0%, #ffce46 7%, #e22d20 27%, #48040b 59%, #060405 73%)",
          opacity: core,
          scale: 0.62 + open * 0.42,
          boxShadow: `0 0 ${42 + ignition * 88}px rgba(255,67,36,${0.42 + ignition * 0.45})`,
        }}
      />

      <div
        style={{
          position: "absolute",
          left: 400,
          top: 400,
          width: 1,
          height: 1,
          opacity: core,
          rotate: `${frame * 2.4}deg`,
        }}
      >
        {Array.from({length: 12}).map((_, index) => (
          <div
            key={index}
            style={{
              position: "absolute",
              left: -30,
              top: -178,
              width: 60,
              height: 126,
              clipPath: "polygon(50% 0,100% 68%,72% 100%,28% 100%,0 68%)",
              background:
                index % 2 === 0
                  ? "linear-gradient(#fff1a3,#d38b19 58%,#3b1c07)"
                  : "linear-gradient(#8b2a17,#f14a25 54%,#2b0606)",
              rotate: `${index * 30}deg`,
              transformOrigin: "30px 178px",
              boxShadow: "0 0 12px rgba(255,186,55,0.38)",
            }}
          />
        ))}
      </div>

      {Array.from({length: 18}).map((_, index) => {
        const angle = -Math.PI / 2 + (index / 18) * Math.PI * 2;
        const radius = 108 + open * (126 + (index % 4) * 24);
        const width = 42 + (index % 4) * 12;
        const height = 64 + (index % 5) * 11;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 400 + Math.cos(angle) * radius - width / 2,
              top: 400 + Math.sin(angle) * radius - height / 2,
              width,
              height,
              clipPath:
                index % 3 === 0
                  ? "polygon(50% 0,100% 74%,30% 100%,0 32%)"
                  : index % 3 === 1
                    ? "polygon(12% 0,100% 24%,72% 100%,0 68%)"
                    : "polygon(48% 0,100% 42%,62% 100%,0 77%,10% 18%)",
              background:
                "linear-gradient(145deg,#5b5148 0%,#201b19 43%,#080708 100%)",
              rotate: `${(angle * 180) / Math.PI + 38 + frame * (index % 2 === 0 ? 0.32 : -0.24)}deg`,
              opacity: open * (0.56 + (index % 4) * 0.1),
              filter:
                "drop-shadow(0 0 3px rgba(255,215,103,0.58)) drop-shadow(0 12px 12px rgba(0,0,0,0.55))",
            }}
          />
        );
      })}

      <KintsugiCracks progress={crack} opacity={1 - open * 0.9} />

      <div
        style={{
          position: "absolute",
          left: 140,
          right: 140,
          top: 397,
          height: 6,
          background:
            "linear-gradient(90deg,transparent,#e8a72b,#fff8c6,#e8a72b,transparent)",
          opacity: ignition,
          scale: `${0.5 + ignition * 0.5} ${1 + ignition * 4}`,
          boxShadow: "0 0 28px #efb635",
        }}
      />

      <ToyotaLogo
        opacity={logoOpacity}
        scale={0.68 + logoOpacity * 0.28}
        size={326}
        colorFilter="sepia(1) saturate(5) hue-rotate(350deg) brightness(1.55)"
        glow="#ffc84a"
      />

      <FilmTexture opacity={0.16} color="255,207,112" />
    </CircleStage>
  );
};

// ---------------------------------------------------------------------------
// 3. ORIGAMI VELOCITY: paper seal -> folded racer -> flight -> logo -> paper
// ---------------------------------------------------------------------------

const carPieces = [
  {clipPath: "polygon(0 72%,52% 0,100% 100%)", left: 205, top: 326, width: 210, height: 142, color: "#f4eee0"},
  {clipPath: "polygon(0 0,100% 28%,32% 100%)", left: 385, top: 328, width: 222, height: 138, color: "#dbd3c4"},
  {clipPath: "polygon(0 0,100% 0,58% 100%,18% 86%)", left: 286, top: 268, width: 234, height: 112, color: "#b71828"},
  {clipPath: "polygon(0 0,100% 36%,88% 100%,20% 86%)", left: 176, top: 402, width: 250, height: 104, color: "#f8f1df"},
  {clipPath: "polygon(8% 0,100% 0,68% 100%,0 84%)", left: 402, top: 399, width: 238, height: 109, color: "#aa1021"},
  {clipPath: "polygon(0 0,100% 52%,16% 100%)", left: 496, top: 315, width: 146, height: 123, color: "#f0e7d8"},
] as const;

const OrigamiCar: React.FC<{
  opacity: number;
  fold: number;
  x: number;
  y: number;
  tilt: number;
  fracture: number;
}> = ({opacity, fold, x, y, tilt, fracture}) => {
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: 800,
        height: 800,
        opacity,
        rotate: `${tilt}deg`,
        scale: 0.72 + fold * 0.28,
      }}
    >
      {carPieces.map((piece, index) => {
        const angle = -2.4 + index * 0.92;
        const spread = fracture * (110 + (index % 3) * 45);
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: piece.left,
              top: piece.top,
              width: piece.width,
              height: piece.height,
              clipPath: piece.clipPath,
              background: `linear-gradient(${115 + index * 18}deg, ${piece.color}, ${index % 2 === 0 ? "#8e0d1d" : "#fffaf0"})`,
              border: "1px solid rgba(56,37,32,0.34)",
              translate: `${Math.cos(angle) * spread}px ${Math.sin(angle) * spread}px`,
              rotate: `${(1 - fold) * (index % 2 === 0 ? -38 : 42) + fracture * (index - 2.5) * 24}deg`,
              filter: "drop-shadow(0 12px 10px rgba(29,12,11,0.28))",
            }}
          />
        );
      })}

      {[300, 525].map((left, index) => (
        <div
          key={left}
          style={{
            position: "absolute",
            left,
            top: 444,
            width: 92,
            height: 92,
            borderRadius: "50%",
            background:
              "radial-gradient(circle,#f4eadb 0 10%,#b61a27 12% 26%,#211718 28% 55%,#070707 58% 100%)",
            opacity: 1 - fracture,
            rotate: `${index === 0 ? -fold * 520 : fold * 520}deg`,
            boxShadow: "0 8px 13px rgba(0,0,0,0.38)",
          }}
        />
      ))}
    </div>
  );
};

export const ToyotaOrigamiVelocity: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const phase = frame / durationInFrames;
  const fold = segment(frame, 18, 82);
  const drive = segment(frame, 72, 145);
  const jump = smoothPulse(frame, 118, 146, 160, 184);
  const fracture = segment(frame, 150, 187);
  const carOpacity = Math.min(segment(frame, 40, 72), 1 - segment(frame, 177, 205));
  const logoOpacity = smoothPulse(frame, 171, 193, 211, 232);
  const paperReturn = segment(frame, 205, 239);
  const sheetOpacity = Math.max(1 - segment(frame, 28, 72), paperReturn);
  const roadMotion = drive * (1 - paperReturn);
  const carX = interpolate(drive, [0, 1], [-100, 78]);
  const carY = -20 - jump * 112;

  return (
    <CircleStage background="radial-gradient(circle at 50% 44%,#f4e5cd 0%,#c9ae8f 44%,#62473d 76%,#181013 100%)">
      <div
        style={{
          position: "absolute",
          left: 243,
          top: 116,
          width: 314,
          height: 314,
          borderRadius: "50%",
          background: "#a90f20",
          opacity: 0.74 - logoOpacity * 0.32,
          scale: 0.96 + Math.sin(phase * Math.PI * 2) * 0.018,
          boxShadow: "0 0 55px rgba(150,15,31,0.23)",
        }}
      />

      <svg
        width={SIZE}
        height={SIZE}
        viewBox="0 0 800 800"
        style={{position: "absolute", inset: 0, opacity: 0.38 + roadMotion * 0.42}}
      >
        {Array.from({length: 9}).map((_, index) => {
          const offset = ((index / 9 + roadMotion * 1.6) % 1) * 420;
          return (
            <path
              key={index}
              d={`M${400 - offset} 790 Q400 ${560 - offset * 0.22} ${400 + offset} 790`}
              fill="none"
              stroke={index % 3 === 0 ? "#9e1524" : "#31201f"}
              strokeWidth={index % 3 === 0 ? 3 : 1}
              opacity={0.18 + index * 0.045}
            />
          );
        })}
        <path
          d="M0 612 Q145 532 292 592 T800 574 L800 800 L0 800Z"
          fill="#3a2825"
          opacity="0.84"
        />
        <path
          d="M0 650 Q180 560 337 625 T800 604"
          fill="none"
          stroke="#e8d7bb"
          strokeWidth="5"
          opacity="0.58"
        />
      </svg>

      {Array.from({length: 14}).map((_, index) => {
        const speed = ((frame * (4 + (index % 4)) + index * 71) % 980) - 90;
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: 800 - speed,
              top: 180 + index * 34,
              width: 70 + (index % 5) * 36,
              height: index % 3 === 0 ? 4 : 2,
              background:
                index % 4 === 0
                  ? "linear-gradient(90deg,transparent,#ae1525)"
                  : "linear-gradient(90deg,transparent,rgba(50,31,28,0.58))",
              opacity: drive * (1 - fracture) * 0.72,
              rotate: "-4deg",
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 214,
          top: 214,
          width: 372,
          height: 372,
          background: "linear-gradient(145deg,#fffaf0,#d8c7ad 58%,#a78e75)",
          opacity: sheetOpacity,
          rotate: `${45 + Math.sin(phase * Math.PI * 2) * 2}deg`,
          scale: 0.9 + sheetOpacity * 0.04,
          boxShadow: "0 24px 55px rgba(41,20,19,0.28)",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            background:
              "linear-gradient(45deg,transparent 49.7%,rgba(85,55,45,0.28) 50%,transparent 50.3%),linear-gradient(-45deg,transparent 49.7%,rgba(85,55,45,0.22) 50%,transparent 50.3%)",
            opacity: 0.76,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 116,
            top: 116,
            width: 140,
            height: 140,
            borderRadius: "50%",
            background: "#b50f24",
            opacity: 0.86,
          }}
        />
      </div>

      <OrigamiCar
        opacity={carOpacity}
        fold={fold}
        x={carX}
        y={carY}
        tilt={-3 - jump * 12}
        fracture={fracture}
      />

      {Array.from({length: 16}).map((_, index) => {
        const shardLife = smoothPulse(frame, 152 + (index % 3) * 2, 169, 199, 222);
        const angle = index * 2.399 + fracture * 2.8;
        const radius = 70 + fracture * (96 + (index % 5) * 25);
        const gather = segment(frame, 184, 213);
        const x = lerp(400 + Math.cos(angle) * radius, 400, gather);
        const y = lerp(390 + Math.sin(angle) * radius * 0.72, 400, gather);
        return (
          <div
            key={index}
            style={{
              position: "absolute",
              left: x - 17,
              top: y - 22,
              width: 34,
              height: 44,
              clipPath:
                index % 2 === 0
                  ? "polygon(0 0,100% 34%,38% 100%)"
                  : "polygon(30% 0,100% 100%,0 72%)",
              background: index % 3 === 0 ? "#a90f20" : "#f5ead7",
              opacity: shardLife,
              rotate: `${index * 47 + frame * (1.7 + (index % 3))}deg`,
              boxShadow: "0 8px 12px rgba(48,24,20,0.24)",
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: 204,
          top: 204,
          width: 392,
          height: 392,
          borderRadius: "50%",
          background:
            "radial-gradient(circle,rgba(255,250,229,0.72),rgba(176,16,34,0.13) 50%,transparent 72%)",
          opacity: logoOpacity,
          scale: 0.74 + logoOpacity * 0.3,
        }}
      />
      <ToyotaLogo
        opacity={logoOpacity}
        scale={0.7 + logoOpacity * 0.28}
        size={360}
        colorFilter="saturate(0.86) brightness(0.78) contrast(1.3)"
        glow="rgba(91,23,28,0.26)"
      />

      <FilmTexture opacity={0.22} color="74,43,37" />
    </CircleStage>
  );
};
