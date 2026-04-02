import { format } from 'date-fns';
import * as XLSX from 'xlsx';

export function exportExcel(vitals: Array<Record<string, unknown>>, t: (key: string) => string) {
  const headers = [
    t('common.date'),
    `${t('vitals.systolic')} (mmHg)`,
    `${t('vitals.diastolic')} (mmHg)`,
    `${t('vitals.pulse')} (bpm)`,
    `${t('vitals.weight')} (kg)`,
    `${t('vitals.temperature')} (\u00B0C)`,
    `${t('vitals.oxygen')} (%)`,
    `${t('vitals.glucose')} (mmol/L)`,
  ];
  const keys = ['measured_at', 'blood_pressure_systolic', 'blood_pressure_diastolic', 'pulse', 'weight', 'body_temperature', 'oxygen_saturation', 'blood_glucose'];
  const rows = vitals.map((v) =>
    keys.map((k) => {
      if (k === 'measured_at') return format(new Date(v[k] as string), 'dd.MM.yyyy HH:mm');
      const val = v[k];
      return val != null ? Number(val) : '';
    })
  );
  const ws = XLSX.utils.aoa_to_sheet([headers, ...rows]);
  ws['!cols'] = headers.map((h) => ({ wch: Math.max(h.length + 2, 14) }));
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, t('vitals.title'));
  XLSX.writeFile(wb, `${t('vitals.title')}_${format(new Date(), 'yyyy-MM-dd')}.xlsx`);
}

export function exportChartPNG(chartRef: React.RefObject<HTMLDivElement | null>) {
  const container = chartRef.current;
  if (!container) return;
  const svg = container.querySelector('svg');
  if (!svg) return;
  const svgData = new XMLSerializer().serializeToString(svg);
  const canvas = document.createElement('canvas');
  const rect = svg.getBoundingClientRect();
  canvas.width = rect.width * 2;
  canvas.height = rect.height * 2;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.scale(2, 2);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, rect.width, rect.height);
  const img = new Image();
  img.onload = () => {
    ctx.drawImage(img, 0, 0, rect.width, rect.height);
    const link = document.createElement('a');
    link.download = `vitalwerte_${format(new Date(), 'yyyy-MM-dd')}.png`;
    link.href = canvas.toDataURL('image/png');
    link.click();
  };
  img.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svgData)));
}
