import {Circle, CircleCheck, Cloud, Plus, RefreshCw, Snowflake, StickyNote, Sun, Trash2, Video} from 'lucide-react';
import {Hairline} from '../components/Glass';
import {agenda, weather} from '../content';
import {clamp01, color, white} from '../theme';

const WEATHER_ICONS = {cloud: Cloud, sun: Sun, snow: Snowflake} as const;
const WEATHER_TINTS = {cloud: color.secondary, sun: color.yellow, snow: color.cyan} as const;
// 真实界面的行首色条按类型写死：普通事件蓝、提醒紫
const KIND_TINT = {event: color.blue, reminder: color.purple} as const;

// Meeting actions belong to the event row; the reminder completion stays independent.
export const AgendaModule = ({done = 0, meeting = false}: {done?: number; meeting?: boolean}) => {
  let reminderIndex = -1;
  const today = agenda.days[agenda.today];
  return (
    <div className="absolute inset-0 flex gap-[12px]">
      <div className="flex shrink-0 flex-col" style={{width: 184}}>
        <div className="flex h-[24px] shrink-0 items-center">
          <div className="text-[12px] font-semibold">Weather</div>
          <div className="flex-1" />
          <RefreshCw size={11} strokeWidth={2.2} color={color.secondary} />
        </div>
        {weather.cities.map((city) => {
          const Icon = WEATHER_ICONS[city.icon];
          return (
            <div key={city.name} className="flex items-center" style={{padding: '5px 0'}}>
              <div style={{width: 22}}>
                <Icon size={17} strokeWidth={2} color={WEATHER_TINTS[city.icon]} />
              </div>
              <div className="min-w-0 flex-1" style={{marginLeft: 4}}>
                <div className="text-[9.5px] leading-[12px] font-semibold">{city.name}</div>
                <div className="truncate text-[8.5px] leading-[11px] text-label-2">
                  {city.condition} · Feels like {city.temp - 1}°
                </div>
              </div>
              <div className="flex flex-col items-end">
                <div className="tabular font-rounded text-[15px] leading-[17px] font-bold">{city.temp}°</div>
                <div className="tabular text-[8.5px] leading-[11px] font-medium text-label-2">
                  {city.low}°–{city.high}°
                </div>
              </div>
            </div>
          );
        })}
        <div className="text-[8px] leading-[11px] text-label-3" style={{marginTop: 2}}>
          Open-Meteo · CC BY 4.0
        </div>
      </div>
      <Hairline vertical />
      <div className="flex min-w-0 flex-1 flex-col">
        <div className="flex h-[24px] shrink-0 items-center gap-[6px]">
          <div className="text-[12px] font-semibold">Calendar and reminders</div>
          <div className="flex-1" />
          <Plus size={12} strokeWidth={2.4} color={color.secondary} />
          <div className="tabular text-[10px] font-medium text-label-2">Nov {today?.day}</div>
        </div>
        <div className="flex h-[28px] shrink-0 gap-[2px]">
          {agenda.days.map((day, index) => {
            const isToday = index === agenda.today;
            return (
              <div
                key={day.day}
                className="flex flex-1 flex-col items-center justify-center"
                style={{height: 26, borderRadius: 6, background: isToday ? white(0.16) : 'transparent', color: isToday ? color.blue : color.label}}
              >
                <div className="text-[9px] leading-[10px] font-medium" style={{opacity: isToday ? 1 : 0.6}}>
                  {day.weekday[0]}
                </div>
                <div className="tabular font-rounded text-[11px] leading-[13px]">{day.day}</div>
              </div>
            );
          })}
        </div>
        <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
          {agenda.items.slice(0, 3).map((item) => {
            const isReminder = item.kind === 'reminder';
            if (isReminder) reminderIndex += 1;
            const checked = isReminder ? clamp01(done - reminderIndex) : 0;
            return (
              <div key={item.title} data-agenda-row={item.title} className="flex h-[34px] shrink-0 items-center gap-[7px]">
                <div style={{width: 3, height: 25, borderRadius: 1.5, background: KIND_TINT[item.kind]}} />
                <div className="min-w-0 flex-1" style={{opacity: 1 - 0.5 * checked}}>
                  <div className="truncate text-[10px] leading-[13px] font-semibold">{item.title}</div>
                  <div className="text-[9px] leading-[12px] text-label-2">{isReminder ? `Reminder · ${item.time || 'Today'}` : meeting && item.title === 'Design review' ? '9:41' : item.time}</div>
                </div>
                {meeting && item.title === 'Design review' ? <><Video size={11} color={color.blue} /><StickyNote data-meeting-note-action size={11} color={color.secondary} /></> : null}
                {isReminder ? (
                  checked > 0.5 ? (
                    <CircleCheck data-reminder-toggle={item.title} size={11} strokeWidth={2.4} color={color.green} />
                  ) : (
                    <Circle data-reminder-toggle={item.title} size={11} strokeWidth={2.4} color={color.green} />
                  )
                ) : null}
                <Trash2 size={10} strokeWidth={2.2} color={color.secondary} />
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
