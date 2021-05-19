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

> - Deux espaces d'adressage : « physique » et « linéaire »^[En mode 64 bits]
> - Le système de mémoire virtuelle permet d'associer à chaque adresse _virtuelle_ une adresse _physique_
> - La granularité de ce système est la « page » : 4096 octets
> - Traduction de linéaire vers physique en décomposant les adresses linéaires en morçeaux :
    * Les 12 derniers bits : adresse dans une page
    * 4*9 bits pour les 4 niveaux de « page tables »^[Vocabulaire non officiel]
> - Les bits de poids forts sont remplis par extension de signe^[Et une adresse non valide provoque une erreur, plusieurs heures de lecture de documentation ont été nécessaires pour obtenir cette information.]

## Organisation des structures de contrôle

> - Les entrées des tables de pages sont chacune stockées sur une page
> - Les tables les plus basses référencent les adresses des pages^[Adresses alignées sur une page, _i.e._ 4Ko]
> - Les tables de niveau supérieur référencent les pages inférieures^[Adresses aussi alignées sur une page]
> - Chaque entrée comporte des fanions indiquant les droits sur la page, principalement :
    * P : Indique que la page est bien présente
    * US : Indique que la page est accessible en mode utilisateur (_ring 3)
    * RW : Indique qu'il est possible d'écrire sur la page^[« If 0, writes may not be allowed »; possiblement ambigu]
    * XD : Pour interdire l'exécution du contenu de la page
> - On peut aussi avoir des « hugepages »^[Vocabulaire non officiel] de 2Mo ou 1Go
> - La page racine^[PML4 chez nous] est référencée par le registre CR3.^[À côté de quelques fanions supplémentaires que nous n'utilisons pas.]

## Application de la mémoire virtuelle

> - On a une grande quantité de mémoire virtuelle disponible
> - Il est d'usage de séparer l'espace d'adressage en deux moitiés :
    * Moitié haute pour le noyau
    * Moitié basse pour l'utilisateur
> - Grâce à la restructuration de la mémoire, on peut faire croire à chaque tâche qu'elle vit seule sur la machine
    * Ceci permet d'avoir des exécutables dont le code _dépend_ de la position en mémoire^[Position des données, des instructions, ...]
    * Permet aussi de simplifier l'agencement de la mémoire pour l'utilisateur: il est beaucoup plus simple de faire grandir la pile par exemple
> - La protection de la mémoire permet d'emêcher les utilisateurs de casser le noyau
> - Elle permet aussi de protéger les utilisateurs les uns des autres

## Note sur les TLBs

> - TLBs : « Translation Lookaside Buffers »
> - Stockent des traduction $\textrm{linéaire} \to \textrm{physique}$
> - Permettent d'éviter de parcourir la hiérarchie de la mémoire virtuelle à chaque accès mémoire
> - Mais doivent êtres gérés à la main : il faut savoir quand les vider
    * `invlpg` permet de vider les traductions associées à une page en particulier
    * On peut aussi vider tous les TLBs en rechargant CR3
> - Ceci doit être fait en paritculier lors de la modification de la structure de la mémoire et lors d'un changement de permissions

# Spécificités UEFI

## Protocoles UEFI

## Obtenir un framebuffer VGA

## Obtenir un accès au disque

## Reconstruire l'IDT, la GDT

# Appels systèmes

# Interruptions
