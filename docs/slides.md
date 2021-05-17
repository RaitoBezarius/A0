---
title: Présentation du projet de systèmes d'exploitation
author: Ryan \textsc{Lahfa}, Théophane \textsc{Vallaeys}, Julien \textsc{Marquet}
lang: fr
advanced-maths: true
advanced-cs: true
theme: metropolis
---

# Introduction au projet

## Nature du système et fonctionnalités 

Un système d'exploitation avec une approche micro-noyau, écrit dans Zig^[Un langage expérimental qui se veut être un remplacement du C pour le bas niveau.] qui cible les plateformes UEFI^[Testé sur OVMF principalement.] pour x86_64.

**Fonctionnalités** :

> - Appels systèmes rapides avec System Call Extensions ;
> - Mémoire virtuelle et PML4 gérée ;
> - Gestion vidéo avec le framebuffer linéaire UEFI, polices de caractères PSF2 intégrée, dessin de texte, « TTY » simple ;
> - Gestion des tâches utilisateur et noyau avec le scheduler de L4
> - Debuggage sur console série, debuggage avec GDB et tous les symboles

## Plan de présentation du système

**Plan de cette soutenance** :

> - x86_64, mémoire virtuelle, protection (Julien)
> - Protocoles UEFI, framebuffer VGA, appels systèmes rapides (Ryan) 
> - Scheduler, tâches, préemptions par interruptions (Théophane)

## Un mot sur Zig

## Difficultés générales

# Mémoire virtuelle en x86_64

## Intérêt de la mémoire virtuelle

## Protection

# Spécificités UEFI

## Protocoles UEFI

## Obtenir un framebuffer VGA

## Obtenir un accès au disque

## Reconstruire l'IDT, la GDT

# Appels systèmes

# Interruptions
