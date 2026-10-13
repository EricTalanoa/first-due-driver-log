import type { Metadata, Viewport } from 'next';
import './globals.css';
export const metadata:Metadata={title:'First Due · Driver’s Log',description:'Your private daily driving and duty log.',manifest:'/manifest.webmanifest',icons:{icon:'/first-due-logo.webp',apple:'/icon-192.png'},appleWebApp:{capable:true,title:'Driver Log',statusBarStyle:'default'}};
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#b52127'};
export default function RootLayout({children}:Readonly<{children:React.ReactNode}>){return <html lang="en"><body>{children}</body></html>;}
