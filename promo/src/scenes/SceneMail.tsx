import {Mail} from 'lucide-react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {Caption} from '../components/Caption';
import {ClickRipple, Cursor} from '../components/Cursor';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {Island, modulePhase} from '../components/Island';
import {IslandBody, StatusHeader, TABS} from '../components/IslandChrome';
import {Camera} from '../components/Stage';
import {typedChars} from '../components/Terminal';
import {MAIL_HEIGHT, MailModule, mailDraft, mailUnreadCount} from '../modules/MailModule';
import {ZislaMotion, ease, fadeWindow, linear, springAt, track} from '../motion';
import {ISLAND, STAGE, black, clamp01, color, islandHeightFor, white} from '../theme';

export const MAIL_DURATION = 540;
export const MAIL_TIMING = {read: 48, compose: 138, to: 162, subject: 207, body: 244, send: 348, sent: 372, allRead: 430} as const;
const OPEN = 14;
const {read: READ, compose: COMPOSE, to: TO, subject: SUBJECT, body: BODY, send: SEND, sent: SENT} = MAIL_TIMING;

const MAIL_ROW = {x: 372, y: 246};
const COMPOSE_BUTTON = {x: 444, y: 155};
const SEND_BUTTON = {x: 974, y: 523};

export const SceneMail = ({duration = MAIL_DURATION}: {duration?: number}) => {
  const frame = Math.min(MAIL_DURATION - 1, useCurrentFrame() * MAIL_DURATION / duration);
  const {fps} = useVideoConfig();
  const selected = frame < READ ? 0 : 1;
  const compose = Math.min(linear(frame, [COMPOSE, COMPOSE + 12], [0, 1]), linear(frame, [SENT, SENT + 12], [1, 0]));
  const reveal = springAt(frame, fps, OPEN, ZislaMotion.islandReveal, 36);
  const moduleIn = clamp01((frame - OPEN - 8) / 24);
  const notice = clamp01(springAt(frame, fps, SENT, ZislaMotion.notice, 24));
  const to = mailDraft.to.slice(0, Math.floor(typedChars(frame, TO, mailDraft.to.length, 48, fps)));
  const subject = mailDraft.subject.slice(0, Math.floor(typedChars(frame, SUBJECT, mailDraft.subject.length, 40, fps)));
  const body = mailDraft.body.slice(0, Math.floor(typedChars(frame, BODY, mailDraft.body.length, 64, fps)));
  const focus = frame < TO || frame >= SEND ? null : frame < SUBJECT ? 'to' : frame < BODY ? 'subject' : 'body';
  const sending = frame >= SEND && frame < SENT;
  const allRead = frame >= MAIL_TIMING.allRead;

  const cursorX = track(frame, [
    [0, 1066],
    [OPEN - 4, 680],
    [OPEN + 18, 680],
    [READ - 12, MAIL_ROW.x],
    [READ + 12, MAIL_ROW.x],
    [COMPOSE - 12, COMPOSE_BUTTON.x],
    [COMPOSE + 16, COMPOSE_BUTTON.x],
    [TO - 8, 577],
    [TO + 24, 577],
    [SUBJECT - 8, 577],
    [BODY - 8, 525],
    [BODY + 30, 525],
    [SEND - 14, SEND_BUTTON.x],
    [SEND + 12, SEND_BUTTON.x],
    [SENT + 34, 1070],
    [MAIL_TIMING.allRead - 15, 420],
    [MAIL_TIMING.allRead + 18, 420],
  ]);
  const cursorY = track(frame, [
    [0, 430],
    [OPEN - 4, 6],
    [OPEN + 18, 6],
    [READ - 12, MAIL_ROW.y],
    [READ + 12, MAIL_ROW.y],
    [COMPOSE - 12, COMPOSE_BUTTON.y],
    [COMPOSE + 16, COMPOSE_BUTTON.y],
    [TO - 8, 219],
    [TO + 24, 219],
    [SUBJECT - 8, 245],
    [BODY - 8, 280],
    [BODY + 30, 280],
    [SEND - 14, SEND_BUTTON.y],
    [SEND + 12, SEND_BUTTON.y],
    [SENT + 34, 577],
    [MAIL_TIMING.allRead - 15, 155],
    [MAIL_TIMING.allRead + 18, 155],
  ]);
  const pressed = [READ, COMPOSE, TO - 6, SUBJECT - 6, BODY - 6, SEND, MAIL_TIMING.allRead].some((at) => frame >= at && frame < at + 6) ? 1 : 0;
  const cursorOpacity = Math.min(linear(frame, [0, 10], [0, 1]), linear(frame, [MAIL_TIMING.allRead + 20, MAIL_TIMING.allRead + 40], [1, 0]));

  return (
    <>
      <Camera scale={ease(frame, [READ + 24, COMPOSE - 12], [1, 1.12])} x={STAGE.width / 2} y={0}>
        <Wallpaper dim={0.14} />
        <MenuBar />
        <Island
          reveal={reveal}
          height={islandHeightFor(MAIL_HEIGHT)}
          wing={40}
          left={<Mail size={17} strokeWidth={2} color={white(0.92)} />}
          right={<span className="tabular text-[12px] font-semibold" style={{color: color.blue}}>{mailUnreadCount(selected, allRead)}</span>}
        >
          <IslandBody header={<StatusHeader />} active={TABS.mail}>
            <div className="absolute inset-0" style={modulePhase(moduleIn, 1, true)}>
              <MailModule frame={frame} selected={selected} compose={compose} to={to} subject={subject} body={body} focus={focus} sending={sending} allRead={allRead} />
            </div>
          </IslandBody>
          {frame >= SENT ? (
            <div
              className="absolute flex items-center rounded-[8px] px-[10px] text-[10.5px] font-medium"
              style={{left: ISLAND.moduleInset, right: ISLAND.moduleInset, bottom: ISLAND.moduleInset, height: 26, background: black(0.62), color: white(0.9), opacity: notice, transform: `translateY(${10 * (1 - notice)}px)`}}
            >
              {allRead ? 'All messages marked as read' : 'Message sent'}
            </div>
          ) : null}
        </Island>
        <Notch />
        <ClickRipple x={MAIL_ROW.x} y={MAIL_ROW.y} progress={linear(frame, [READ, READ + 22], [0, 1])} />
        <ClickRipple x={COMPOSE_BUTTON.x} y={COMPOSE_BUTTON.y} progress={linear(frame, [COMPOSE, COMPOSE + 22], [0, 1])} />
        <ClickRipple x={SEND_BUTTON.x} y={SEND_BUTTON.y} progress={linear(frame, [SEND, SEND + 22], [0, 1])} />
        <Cursor x={cursorX} y={cursorY} pressed={pressed} opacity={cursorOpacity} />
      </Camera>
      <Caption text="Read, write, send. Mark the inbox read in one click." opacity={fadeWindow(frame, OPEN + 22, MAIL_DURATION - 1, 14)} bottom={40} />
    </>
  );
};
