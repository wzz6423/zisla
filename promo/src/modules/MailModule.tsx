import {
  CircleCheck,
  CircleEllipsis,
  CircleX,
  Image as ImageIcon,
  ListFilter,
  LoaderCircle,
  Paperclip,
  RefreshCw,
  Reply,
  Send,
  SquarePen,
} from 'lucide-react';
import {GlassPanel, IconButton} from '../components/Glass';
import {color, white} from '../theme';

// AppModel.swift uses the shared 401 pt system layout for MailModuleView.
export const MAIL_HEIGHT = 401;

const CONTACT = {name: 'Mira Solen', address: 'mira.solen@example.com'};

export const mailDraft = {
  from: 'alex.hale@example.com',
  to: CONTACT.address,
  subject: 'Design review · 10:30',
  body: 'Hi Mira,\n\nThe updated island study is ready.\nSee you at 10:30.\n\nAlex',
} as const;

const MESSAGES = [
  {
    sender: 'Evan Hale <evan.hale@example.com>',
    title: 'Workshop notes',
    preview: 'The motion notes are ready for the next pass.',
    received: 'Nov 11, 8:52 AM',
    unread: false,
    body: 'Hi Alex,\n\nThe motion notes are ready for the next pass.\nThe updated sketches are in our shared folder.\n\nThanks,\nEvan',
  },
  {
    sender: `${CONTACT.name} <${CONTACT.address}>`,
    title: mailDraft.subject,
    preview: 'Can you bring the updated island study?',
    received: 'Nov 11, 9:38 AM',
    unread: true,
    body: 'Hi Alex,\n\nCan you bring the updated island study to our 10:30 review?\n\nWe’ll look at the hover reveal, the mail composer, and the final export.\n\nThanks,\nMira',
  },
  {
    sender: 'Noah Vale <noah.vale@example.com>',
    title: 'Launch film assets',
    preview: 'The final artwork is in the shared folder.',
    unread: true,
  },
  {
    sender: 'Lina Park <lina.park@example.com>',
    title: 'Coffee after the review?',
    preview: 'I’ll meet you downstairs at eleven.',
    unread: false,
  },
  {
    sender: 'Rowan Lee <rowan.lee@example.com>',
    title: 'Release schedule',
    preview: 'Let’s keep the afternoon clear for the export.',
    unread: true,
  },
  {
    sender: 'Ivy Chen <ivy.chen@example.com>',
    title: 'Notes from yesterday',
    preview: 'A few thoughts on the new island transitions.',
    unread: false,
  },
] as const;

export const mailUnreadCount = (selected: 0 | 1, allRead = false): number =>
  allRead ? 0 : MESSAGES.filter((item, index) => item.unread && !(index === 1 && selected === 1)).length;

type MailModuleProps = {
  frame: number;
  selected: 0 | 1;
  compose: number;
  to: string;
  subject: string;
  body: string;
  focus: 'to' | 'subject' | 'body' | null;
  sending: boolean;
  allRead?: boolean;
};

const MailCaret = ({frame}: {frame: number}) => (
  <span
    className="inline-block"
    style={{width: 1, height: 13, marginLeft: 1, verticalAlign: '-2px', background: color.blue, opacity: frame % 34 < 22 ? 1 : 0.05}}
  />
);

export const MailModule = ({frame, selected, compose, to, subject, body, focus, sending, allRead = false}: MailModuleProps) => {
  const message = MESSAGES[selected];
  const ready = body.trim().length > 0;

  return (
    <div className="absolute inset-0 flex">
      <div className="flex shrink-0 flex-col" style={{width: 232, paddingRight: 8}}>
        <div className="flex h-[28px] shrink-0 items-center gap-[4px] px-[4px]">
          <span className="text-[12px] font-semibold">Mail</span>
          <span className="tabular text-[9px] font-bold" style={{color: color.blue}}>{mailUnreadCount(selected, allRead)}</span>
          <IconButton compact icon={ListFilter} />
          <div className="min-w-[2px] flex-1" />
          <IconButton compact icon={CircleCheck} />
          <IconButton compact icon={SquarePen} />
          <IconButton compact icon={RefreshCw} />
        </div>
        <div className="flex min-h-0 flex-1 flex-col">
          {MESSAGES.map((item, index) => {
            const unread = !allRead && item.unread && !(index === 1 && selected === 1);
            return (
              <div
                key={item.title}
                className="flex shrink-0 flex-col gap-[2px] rounded-[7px]"
                style={{padding: '6px 8px', background: selected === index && compose < 0.01 ? white(0.16) : 'transparent'}}
              >
                <div className="flex items-center gap-[4px]">
                  <div className="h-[5px] w-[5px] shrink-0 rounded-full" style={{background: unread ? color.blue : 'transparent'}} />
                  <span className="min-w-0 truncate text-[10.5px] leading-[13px]" style={{fontWeight: unread ? 600 : 500}}>{item.sender}</span>
                </div>
                <div className="truncate text-[9px] leading-[11px]" style={{fontWeight: unread ? 600 : 400, color: unread ? color.label : color.secondary}}>{item.title}</div>
                <div className="truncate text-[9px] leading-[11px] text-label-3">{item.preview}</div>
              </div>
            );
          })}
        </div>
      </div>

      <div className="relative min-w-0 flex-1" style={{marginLeft: 10}}>
        {compose < 1 ? (
          <div className="absolute inset-0 flex flex-col" style={{opacity: 1 - compose, transform: `translateX(${-18 * compose}px)`}}>
            <div className="flex shrink-0 items-start gap-[8px]" style={{minHeight: 42, paddingBottom: 6}}>
              <div className="flex min-w-0 flex-1 flex-col gap-[2px]">
                <span className="text-[12px] leading-[15px] font-semibold">{message.title}</span>
                <span className="truncate text-[9px] leading-[11px] text-label-2">{message.sender}</span>
                <span className="truncate text-[9px] leading-[11px] text-label-3">Studio · {message.received}</span>
              </div>
              <div className="flex shrink-0 items-center gap-[6px]">
                <div className="flex items-center gap-[4px] rounded-[5px] px-[6px] py-[4px] text-[9px] leading-[11px] font-semibold" style={{background: color.fillControl}}>
                  <Reply size={10} strokeWidth={2.2} />
                  <span>Reply</span>
                </div>
                <CircleEllipsis size={13} strokeWidth={2.2} color={color.secondary} />
              </div>
            </div>
            <GlassPanel
              radius={8}
              tint={white(0.05)}
              className="relative min-h-0 flex-1"
              style={{position: 'relative', borderRadius: '8px 8px 22px 8px', boxShadow: 'none', padding: 10}}
            >
              <div className="whitespace-pre-line text-[11px] leading-[17px]" style={{color: white(0.9)}}>{message.body}</div>
            </GlassPanel>
          </div>
        ) : null}

        {compose > 0 ? (
          <div className="absolute inset-0 flex flex-col" style={{opacity: compose, transform: `translateX(${18 * (1 - compose)}px)`}}>
            <div className="flex h-[32px] shrink-0 items-center gap-[5px] px-[4px]">
              <SquarePen size={13} strokeWidth={2.2} color={color.blue} />
              <span className="text-[13px] font-semibold" style={{color: color.blue}}>New Message</span>
              <div className="flex-1" />
              <CircleX size={16} strokeWidth={2} color={color.secondary} />
            </div>
            <div className="flex min-h-0 flex-1 flex-col gap-[10px] py-[12px]">
              <div className="flex h-[16px] shrink-0 items-center gap-[6px]">
                <span className="w-[52px] shrink-0 text-[10px] font-medium text-label-2">From</span>
                <span className="text-[11px] font-medium">{mailDraft.from}</span>
                <span className="text-[9px] text-label-3">· Studio</span>
              </div>
              <div className="flex h-[16px] shrink-0 items-center gap-[6px]">
                <span className="w-[52px] shrink-0 text-[10px] font-medium text-label-2">To</span>
                <span className="min-w-0 truncate text-[11px]" style={{color: to.length > 0 || focus === 'to' ? color.label : color.tertiary}}>
                  {to.length > 0 || focus === 'to' ? to : 'Separate addresses with commas'}
                  {focus === 'to' ? <MailCaret frame={frame} /> : null}
                </span>
              </div>
              <div className="flex h-[16px] shrink-0 items-center gap-[6px]">
                <span className="w-[52px] shrink-0 text-[10px] font-medium text-label-2">Subject</span>
                <span className="min-w-0 truncate text-[11px]" style={{color: subject.length > 0 || focus === 'subject' ? color.label : color.tertiary}}>
                  {subject.length > 0 || focus === 'subject' ? subject : 'Message subject'}
                  {focus === 'subject' ? <MailCaret frame={frame} /> : null}
                </span>
              </div>
              <GlassPanel
                radius={8}
                tint={color.fillControl}
                className="relative flex-1"
                style={{position: 'relative', minHeight: 180, boxShadow: 'none', padding: 8}}
              >
                <div className="whitespace-pre-line text-[12px] leading-[18px]">
                  {body}
                  {focus === 'body' ? <MailCaret frame={frame} /> : null}
                </div>
              </GlassPanel>
            </div>
            <div className="flex h-[38px] shrink-0 items-center gap-[4px] px-[8px] py-[6px]">
              <div className="flex items-center gap-[4px] rounded-[5px] px-[6px] py-[4px] text-[10.5px] leading-[13px]" style={{background: color.fillControl}}>
                <Paperclip size={11} strokeWidth={2.1} />
                <span>Add File</span>
              </div>
              <div className="flex items-center gap-[4px] rounded-[5px] px-[6px] py-[4px] text-[10.5px] leading-[13px]" style={{background: color.fillControl}}>
                <ImageIcon size={11} strokeWidth={2.1} />
                <span>Add Image</span>
              </div>
              <div className="h-[16px] w-px" style={{marginLeft: 4, background: color.divider}} />
              <div className="flex-1" />
              <div className="flex h-[26px] items-center rounded-[6px] px-[10px] text-[11px]" style={{marginRight: 4, background: color.fillControl}}>Cancel</div>
              <div
                className="flex h-[26px] w-[68px] shrink-0 items-center justify-center gap-[5px] rounded-[6px] text-[11px] font-medium"
                style={{background: ready ? color.blue : color.fillControl, color: ready ? color.label : color.tertiary}}
              >
                {sending ? <LoaderCircle size={12} strokeWidth={2.2} style={{transform: `rotate(${frame * 12}deg)`}} /> : <><Send size={11} strokeWidth={2.1} /><span>Send</span></>}
              </div>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
};
