import {useMemo} from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  interpolateColors,
  useCurrentFrame,
} from "remotion";

type Point = readonly [number, number];

const CENTER = 400;
const POINTS = 24;
const BLACK = "#111214";
const COOL_GRAY = "#d7dde1";

const mix = (from: number, to: number, progress: number) =>
  from + (to - from) * progress;

const ellipsePoints = (
  cx: number,
  cy: number,
  rx: number,
  ry: number,
  startAngle: number,
  endAngle: number,
  count: number,
): Point[] =>
  Array.from({length: count}, (_, index) => {
    const progress = index / (count - 1);
    const angle = mix(startAngle, endAngle, progress);
    return [cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry];
  });

const radialPoints = (angle: number, length: number, count: number): Point[] =>
  Array.from({length: count}, (_, index) => {
    const radius = (index / (count - 1)) * length;
    return [
      CENTER + Math.cos(angle) * radius,
      CENTER + Math.sin(angle) * radius,
    ];
  });

const morphPoints = (from: Point[], to: Point[], progress: number): Point[] =>
  from.map((point, index) => [
    mix(point[0], to[index][0], progress),
    mix(point[1], to[index][1], progress),
  ]);

const openSpline = (points: Point[]) => {
  const first = points[0];
  let path = `M ${first[0].toFixed(2)} ${first[1].toFixed(2)}`;

  for (let index = 0; index < points.length - 1; index++) {
    const previous = points[Math.max(0, index - 1)];
    const current = points[index];
    const next = points[index + 1];
    const after = points[Math.min(points.length - 1, index + 2)];
    const control1X = current[0] + (next[0] - previous[0]) / 6;
    const control1Y = current[1] + (next[1] - previous[1]) / 6;
    const control2X = next[0] - (after[0] - current[0]) / 6;
    const control2Y = next[1] - (after[1] - current[1]) / 6;
    path += ` C ${control1X.toFixed(2)} ${control1Y.toFixed(2)}, ${control2X.toFixed(2)} ${control2Y.toFixed(2)}, ${next[0].toFixed(2)} ${next[1].toFixed(2)}`;
  }

  return path;
};

const closedSpline = (points: Point[]) => {
  const first = points[0];
  let path = `M ${first[0].toFixed(2)} ${first[1].toFixed(2)}`;

  for (let index = 0; index < points.length; index++) {
    const previous = points[(index - 1 + points.length) % points.length];
    const current = points[index];
    const next = points[(index + 1) % points.length];
    const after = points[(index + 2) % points.length];
    const control1X = current[0] + (next[0] - previous[0]) / 6;
    const control1Y = current[1] + (next[1] - previous[1]) / 6;
    const control2X = next[0] - (after[0] - current[0]) / 6;
    const control2Y = next[1] - (after[1] - current[1]) / 6;
    path += ` C ${control1X.toFixed(2)} ${control1Y.toFixed(2)}, ${control2X.toFixed(2)} ${control2Y.toFixed(2)}, ${next[0].toFixed(2)} ${next[1].toFixed(2)}`;
  }

  return `${path} Z`;
};

const loop = (rx: number, ry = rx, cy = CENTER) =>
  ellipsePoints(CENTER, cy, rx, ry, 0, Math.PI * 2, POINTS + 1).slice(0, -1);

const halfLoop = (
  cx: number,
  cy: number,
  rx: number,
  ry: number,
  from: number,
  to: number,
) => ellipsePoints(cx, cy, rx, ry, from, to, POINTS);

const wheelOuter = loop(274);
const logoOuter = loop(310, 194);
const ringOuter = loop(226);
const ringMiddle = ellipsePoints(
  CENTER,
  CENTER,
  164,
  164,
  0,
  Math.PI * 2,
  POINTS,
);
const ringInner = loop(100);

const verticalLeft = halfLoop(CENTER, 403, 63, 168, -Math.PI / 2, (-Math.PI * 3) / 2);
const verticalRight = halfLoop(CENTER, 403, 63, 168, -Math.PI / 2, Math.PI / 2);
const horizontalTop = halfLoop(CENTER, 310, 226, 75, Math.PI, Math.PI * 2);
const horizontalBottom = halfLoop(CENTER, 310, 226, 75, Math.PI, 0);
const logoVertical = loop(63, 168, 403);

const spokeLeft = radialPoints(-Math.PI / 2, 258, POINTS);
const spokeRight = radialPoints(Math.PI / 6, 258, POINTS);
const spokeTop = radialPoints((Math.PI * 5) / 6, 258, POINTS);

const AnimatedPath: React.FC<{
  from: Point[];
  to: Point[];
  progress: number;
  closed?: boolean;
  strokeFrom: number;
  strokeTo: number;
  colorFrom: string;
  colorTo: string;
}> = ({
  from,
  to,
  progress,
  closed = false,
  strokeFrom,
  strokeTo,
  colorFrom,
  colorTo,
}) => {
  const points = morphPoints(from, to, progress);
  const path = closed ? closedSpline(points) : openSpline(points);

  return (
    <path
      d={path}
      fill="none"
      stroke={interpolateColors(progress, [0, 1], [colorFrom, colorTo])}
      strokeWidth={mix(strokeFrom, strokeTo, progress)}
      strokeLinecap="round"
      strokeLinejoin="round"
      vectorEffect="non-scaling-stroke"
    />
  );
};

export const ToyotaWheelMorph: React.FC = () => {
  const frame = useCurrentFrame();
  const morph = interpolate(frame, [66, 258], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.65, 0, 0.18, 1),
  });
  const ringMorph = interpolate(frame, [78, 264], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.62, 0, 0.2, 1),
  });
  const rotation = interpolate(frame, [0, 270], [0, 720], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.56, 0.02, 0.18, 1),
  });

  const paths = useMemo(
    () => ({
      outer: morphPoints(wheelOuter, logoOuter, morph),
      ringOuter: morphPoints(ringOuter, logoOuter, ringMorph),
      ringMiddle: morphPoints(ringMiddle, horizontalBottom, ringMorph),
      ringInner: morphPoints(ringInner, logoVertical, ringMorph),
    }),
    [morph, ringMorph],
  );

  return (
    <AbsoluteFill style={{backgroundColor: "#ffffff"}}>
      <svg
        width="800"
        height="800"
        viewBox="0 0 800 800"
        style={{
          position: "absolute",
          inset: 0,
          rotate: `${rotation}deg`,
          transformOrigin: "400px 400px",
        }}
        aria-label="Wheel transforming continuously into the Toyota emblem"
      >
        <path
          d={closedSpline(paths.ringOuter)}
          fill="none"
          stroke={interpolateColors(ringMorph, [0, 1], [COOL_GRAY, BLACK])}
          strokeWidth={mix(5, 30, ringMorph)}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <path
          d={openSpline(paths.ringMiddle)}
          fill="none"
          stroke={interpolateColors(ringMorph, [0, 1], [COOL_GRAY, BLACK])}
          strokeWidth={mix(5, 31, ringMorph)}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <path
          d={closedSpline(paths.ringInner)}
          fill="none"
          stroke={interpolateColors(ringMorph, [0, 1], [COOL_GRAY, BLACK])}
          strokeWidth={mix(5, 31, ringMorph)}
          strokeLinecap="round"
          strokeLinejoin="round"
        />

        <AnimatedPath
          from={spokeLeft}
          to={verticalLeft}
          progress={morph}
          strokeFrom={18}
          strokeTo={36}
          colorFrom={BLACK}
          colorTo={BLACK}
        />
        <AnimatedPath
          from={spokeRight}
          to={verticalRight}
          progress={morph}
          strokeFrom={18}
          strokeTo={36}
          colorFrom={BLACK}
          colorTo={BLACK}
        />
        <AnimatedPath
          from={spokeTop}
          to={horizontalTop}
          progress={morph}
          strokeFrom={18}
          strokeTo={36}
          colorFrom={BLACK}
          colorTo={BLACK}
        />

        <path
          d={closedSpline(paths.outer)}
          fill="none"
          stroke={BLACK}
          strokeWidth={mix(25, 36, morph)}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </AbsoluteFill>
  );
};
