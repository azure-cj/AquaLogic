export type VisitorRule = {
  id: 'glass' | 'flash' | 'feeding' | 'questions';
  title: string;
  body: string;
};

export type PublicFaq = {
  question: string;
  answer: string;
};

export type BusinessProfile = {
  name: string;
  tagline: string;
  address: string;
  phone?: string;
  email?: string;
  socialUrl?: string;
  socialLabel?: string;
  openingHours?: Array<{ days: string; hours: string; }>;
};

export const visitorRules: VisitorRule[] = [
  {
    id: 'glass',
    title: "Please don't tap the glass",
    body: 'Sudden vibrations can stress fish and disturb their natural behavior.',
  },
  {
    id: 'flash',
    title: 'No flash photography',
    body: 'Bright flashes can startle the inhabitants. Natural-light photos are welcome.',
  },
  {
    id: 'feeding',
    title: 'Ask before feeding',
    body: 'Each tank follows a measured feeding plan to protect fish health and water quality.',
  },
  {
    id: 'questions',
    title: 'Curious? Just ask',
    body: 'Our team enjoys talking about aquatics and the species in our care.',
  },
];

export const publicFaqs: PublicFaq[] = [
  {
    question: 'Are the fish for sale?',
    answer:
      'Some fish are part of permanent displays, while others may be available. Please ask a team member about the species you like.',
  },
  {
    question: 'How often is the water tested?',
    answer:
      'AquaLogic monitors key conditions throughout the day, and the JRed team also performs routine hands-on checks.',
  },
  {
    question: 'Can children get close to the tanks?',
    answer:
      'Absolutely. Please supervise young visitors and remind them not to tap the glass or reach into the aquarium.',
  },
  {
    question: 'Do you offer aquarium setup services?',
    answer:
      'JRed Aquatics provides aquarium supplies and maintenance services. Ask the team in store for the options available for your space.',
  },
];

export const businessProfile: BusinessProfile = {
  name: 'JRed Aquatics',
  tagline: 'Ornamental fish care · Aquarium supplies · Maintenance',
  address: 'Villa Magdalena, Camarin Road, Novaliches, Caloocan City',
};
