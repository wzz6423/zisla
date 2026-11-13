import {Check, ChevronDown, Grip, Image as ImageIcon, PawPrint} from 'lucide-react';
import {Img, useCurrentFrame, useVideoConfig} from 'remotion';
import {Caption, Headline} from '../components/Caption';
import {ClickRipple, Cursor} from '../components/Cursor';
import {MenuBar, Notch, Wallpaper} from '../components/Desktop';
import {GlassPanel, Hairline} from '../components/Glass';
import {Island} from '../components/Island';
import {ProviderLogo} from '../components/IslandChrome';
import {fadeWindow, linear} from '../motion';
import {black, clamp01, color, white} from '../theme';
import {LAYOUTS_DURATION, LAYOUT_SETTINGS, PLACEMENT_CONFIRM, layoutPets, layoutStateAt, petMotionAt} from './layoutsState';
import type {LayoutState} from './layoutsState';

export const LayoutPet = ({pet, frame, fps, size}: {pet: typeof layoutPets[keyof typeof layoutPets]; frame: number; fps: number; size: number}) => {
  const motion = petMotionAt(frame, fps);
  return (
    <Img
      src={pet.src}
      data-pet-id={pet.id}
      data-pet-frame={0}
      style={{width: size * pet.width / pet.height, height: size, objectFit: 'contain', imageRendering: 'pixelated', transform: `translateY(${motion.lift * size}px) scale(${motion.scale})`}}
    />
  );
};

const FloatingPill = ({state}: {state: LayoutState}) => {
  const vertical = state.placement.edge === 'left' || state.placement.edge === 'right';
  const camera = state.placement.mode === 'camera';
  return (
    <div className="absolute" data-feature={camera ? 'island.camera' : `island.custom.${state.placement.edge}`} data-layout-style="pill" data-placement={state.placement.mode} data-placement-stage={state.editing ? 'preview' : 'committed'} data-edge={state.placement.edge} style={{left: state.rect.x, top: state.rect.y, width: state.rect.width, height: state.rect.height}}>
      <GlassPanel radius={state.editing ? 12 : 16} tint="#000" className="flex items-center" style={{inset: 0, justifyContent: camera ? 'space-between' : 'center', flexDirection: vertical ? 'column' : 'row', gap: state.editing ? 0 : 6, padding: state.editing ? 0 : camera ? '0 12px' : vertical ? '12px 4px' : '4px 12px', border: 'none', boxShadow: `inset 0 0 0 ${state.editing ? 2 : 1}px ${state.editing ? color.blue : color.strokeCard}`}}>
        {state.editing ? (
          <div className="flex gap-[2px]">
            {[0, 1, 2].map((dot) => <span key={dot} className="rounded-full" style={{width: 3, height: 3, background: white(0.8)}} />)}
          </div>
        ) : (
          <>
            <ProviderLogo provider="claude" size={24} />
            <span className="font-rounded tabular text-[11px] font-medium" data-active-tasks={3}>3</span>
          </>
        )}
      </GlassPanel>
    </div>
  );
};

const SelectControl = ({value, choices, open, selected}: {value: string; choices: readonly string[]; open: boolean; selected: number}) => (
  <div className="relative shrink-0" style={{width: 158}}>
    <div className="flex h-[26px] items-center justify-between gap-2 rounded-[6px] px-2 text-[11px] font-medium" style={{background: color.fillControl, border: `1px solid ${white(0.1)}`}}>
      <span className="truncate">{value}</span>
      <ChevronDown size={12} className="shrink-0 text-label-2" />
    </div>
    {open ? (
      <GlassPanel radius={8} tint="rgba(34,34,38,0.96)" style={{left: 0, top: 34, width: 188, zIndex: 3, padding: 4}}>
        {choices.map((choice, index) => (
          <div key={choice} className="flex h-[34px] items-center gap-[6px] rounded-[4px] px-[6px] text-[11px] font-medium">
            <Check size={11} style={{opacity: index === selected ? 1 : 0}} />
            {choice}
          </div>
        ))}
      </GlassPanel>
    ) : null}
  </div>
);

const SettingsWindow = ({state, frame, fps}: {state: LayoutState; frame: number; fps: number}) => (
  <GlassPanel radius={12} tint="rgba(28,28,32,0.92)" style={{left: LAYOUT_SETTINGS.x, top: LAYOUT_SETTINGS.y, width: LAYOUT_SETTINGS.width, padding: 20, overflow: 'visible'}}>
    <div className="mb-3 flex h-[24px] items-center gap-[9px] text-[16px] font-semibold">
      {state.pets ? <PawPrint size={18} /> : <Grip size={18} />}
      <span>{state.pets ? 'Pets' : 'Island style'}</span>
      <span className="ml-auto text-[10px] font-medium text-label-2">zisla Settings</span>
    </div>
    {state.pets ? (
      <>
        <div className="flex h-[40px] items-center justify-between text-[12px]">
          <span>Current pet</span>
          <SelectControl value={state.petName} choices={['Bear', 'Chick']} selected={state.pet.id === 'bear' ? 0 : 1} open={state.menu === 'pet'} />
        </div>
        <Hairline />
        <div className="flex h-[40px] items-center justify-between text-[12px]">
          <span>Import pet</span>
          <div className="flex h-[26px] w-[158px] items-center justify-center rounded-[6px] text-[11px] font-medium" style={{background: color.fillControl}}>Choose file</div>
        </div>
        <Hairline />
        <div className="flex h-[40px] items-center justify-between text-[12px]">
          <span>Side of the island</span>
          <SelectControl value={state.petSide === 'left' ? 'Left' : 'Right'} choices={['Left', 'Right']} selected={state.petSide === 'left' ? 0 : 1} open={state.menu === 'side'} />
        </div>
        <Hairline />
        <div className="mt-4 flex items-center gap-4">
          <div className="flex h-[72px] w-[90px] items-center justify-center rounded-[8px]" style={{background: color.fillControl}}>
            <LayoutPet pet={state.pet} frame={frame} fps={fps} size={56} />
          </div>
          <div className="flex flex-col gap-[4px]">
            <span className="text-[15px] font-semibold">{state.petName}</span>
            <span className="text-[11px] text-label-2">Images and videos · up to 30 seconds</span>
          </div>
        </div>
      </>
    ) : (
      <>
        <div className="flex h-[40px] items-center justify-between text-[12px]">
          <span>Island style</span>
          <SelectControl value={state.style === 'notch' ? 'Notch mode' : 'Dynamic Island mode'} choices={['Notch mode', 'Dynamic Island mode']} selected={state.style === 'notch' ? 0 : 1} open={state.menu === 'style'} />
        </div>
        {state.style === 'pill' ? (
          <>
            <Hairline />
            <div className="flex h-[40px] items-center justify-between text-[12px]">
              <span>Island position</span>
              <SelectControl value={state.placement.mode === 'camera' ? 'Camera position' : 'Custom position'} choices={['Camera position', 'Custom position']} selected={state.placement.mode === 'camera' ? 0 : 1} open={state.menu === 'position'} />
            </div>
            {state.placement.mode === 'custom' ? (
              <>
                <Hairline />
                <div className="flex h-[40px] items-center justify-between text-[12px]">
                  <span>{state.placement.edge.charAt(0).toUpperCase() + state.placement.edge.slice(1)} edge</span>
                  <div className="flex h-[26px] w-[158px] items-center justify-center rounded-[6px] text-[11px] font-medium" style={{background: color.fillControl}}>Adjust position</div>
                </div>
              </>
            ) : null}
          </>
        ) : null}
      </>
    )}
  </GlassPanel>
);

const PlacementOverlay = () => (
  <>
    <div className="absolute inset-0" style={{background: 'rgba(76,76,76,0.65)'}} />
    <div className="absolute flex flex-col items-center gap-4" style={{left: 360, top: 399, width: 560}}>
      <div className="text-center text-[15px] font-medium">Drag the pill to a screen edge. Press Return to finish or Esc to cancel.</div>
      <div className="flex gap-3">
        <div className="rounded-[6px] px-[18px] py-[7px] text-[12px] font-medium" style={{background: white(0.16)}}>Cancel</div>
        <div className="rounded-[6px] px-[22px] py-[7px] text-[12px] font-medium" style={{background: color.blue}}>Done</div>
      </div>
    </div>
  </>
);

const PetImportSheet = ({state, frame, fps}: {state: LayoutState; frame: number; fps: number}) => (
  <>
    <div className="absolute inset-0" data-feature="pet.import" data-import-stage={state.importStage} style={{background: black(0.42)}} />
    <GlassPanel radius={12} tint="rgba(32,32,36,0.96)" style={{left: 440, top: 272, width: 400, padding: 24}}>
      <div className="mb-4 h-[24px] text-[18px] leading-[24px] font-semibold">{state.importStage === 'file' ? 'Choose a pet image' : 'Import pet'}</div>
      <div className="mb-4 flex h-[32px] items-center gap-3 text-[13px]">
        <ImageIcon size={20} color={color.blue} />
        <span>Pocket Chick.png</span>
        <div className="ml-auto"><LayoutPet pet={layoutPets.chick} frame={frame} fps={fps} size={32} /></div>
      </div>
      {state.importStage === 'file' ? (
        <>
          <div className="h-[16px] text-[11px] text-label-2">Images and videos</div>
          <div className="mt-4 flex justify-end text-[12px] font-medium"><span className="rounded-[6px] px-4 py-[7px]" style={{background: color.blue}}>Open</span></div>
        </>
      ) : (
        <>
          <div className="mb-[5px] h-[14px] text-[11px] leading-[14px] text-label-2">Pet name</div>
          <div className="h-[32px] rounded-[6px] border px-2 py-[6px] text-[13px]" style={{background: white(0.06), borderColor: color.blue}}>{state.name}<span style={{opacity: state.importStage === 'name' ? 1 : 0}}>|</span></div>
          <div className="mt-3 h-[32px] text-[11px] leading-[16px] text-label-2">Images and videos · up to 30 seconds · 100 MB maximum</div>
          <div className="mt-5 flex h-[30px] items-center justify-end gap-3 text-[12px] font-medium">
            <span className="mr-auto text-label-2">{state.importStage === 'processing' ? 'Importing…' : ''}</span>
            <span className="rounded-[6px] px-3 py-[6px]" style={{background: color.fillControl}}>Cancel</span>
            <span className="rounded-[6px] px-3 py-[6px]" style={{background: color.blue}}>Import pet</span>
          </div>
        </>
      )}
    </GlassPanel>
  </>
);

export const SceneLayouts = ({duration = LAYOUTS_DURATION}: {duration?: number; globalFrom?: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const state = layoutStateAt(frame, duration);
  const label = state.pets ? `${state.petName} · ${state.petSide === 'left' ? 'Left' : 'Right'} side`
    : state.style === 'notch' ? 'Notch mode'
      : state.placement.mode === 'camera' ? 'Dynamic Island mode · Camera position'
        : `Dynamic Island mode · Custom position · ${state.placement.edge.charAt(0).toUpperCase() + state.placement.edge.slice(1)} edge`;
  return (
    <>
      <Wallpaper dim={0.1} />
      <MenuBar appName="zisla" menus={['File', 'Edit', 'View', 'Window', 'Help']} />
      <Headline lines={[state.pets ? 'A companion on either side.' : 'Choose your island. Place it where you work.']} top={108} size={38} opacity={clamp01(linear(state.local, [8, 28], [0, 1]))} />
      <div className="absolute inset-x-0 text-center text-[18px] font-medium" style={{top: 173, color: white(0.82)}}>{label}</div>
      {state.editing ? <PlacementOverlay /> : <SettingsWindow state={state} frame={frame} fps={fps} />}
      {state.style === 'notch' ? (
        <div data-feature="island.notch" data-layout-style="notch" data-placement="camera" data-edge="top">
          <Island reveal={0} height={34} wing={40} left={<ProviderLogo provider="claude" size={20} />} right={<span className="text-[12px] font-semibold" data-active-tasks={3}>3</span>} />
        </div>
      ) : <FloatingPill state={state} />}
      <Notch />
      {!state.editing && state.placement.mode === 'custom' ? <div data-feature="island.custom.confirmed" data-edge={state.placement.edge} /> : null}
      {state.pets ? (
        <div className="absolute" data-feature={`pet.${state.petSide}`} data-pet-side={state.petSide} style={{left: state.petRect.x, top: state.petRect.y}}>
          <LayoutPet pet={state.pet} frame={frame} fps={fps} size={state.petRect.height} />
        </div>
      ) : null}
      {state.importStage === 'imported' ? <div data-feature="pet.imported" data-pet-name={state.petName} /> : null}
      {state.importStage === 'file' || state.importStage === 'name' || state.importStage === 'processing' ? <PetImportSheet state={state} frame={frame} fps={fps} /> : null}
      <Cursor x={state.cursor.x} y={state.cursor.y} pressed={state.pressed ? 1 : 0} opacity={clamp01(linear(state.local, [0, 12], [0, 1]))} />
      <ClickRipple x={PLACEMENT_CONFIRM.x} y={PLACEMENT_CONFIRM.y} progress={state.confirmation} />
      <Caption text={state.pets ? 'Built-in companions. Import your own images or videos.' : 'Notch mode, camera position, or any screen edge.'} opacity={fadeWindow(state.local, 30, LAYOUTS_DURATION - 8, 14)} bottom={60} size={16} />
      {state.pets ? <div className="absolute inset-x-0 text-center text-[9px] text-label-2" style={{bottom: 6}}>Pet art: Kenney Animal Pack Redux · CC0 1.0</div> : null}
    </>
  );
};
